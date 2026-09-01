// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {CrapsViews} from "./CrapsViews.sol";
import {CrapsPins} from "./CrapsPins.sol";
import {Vm} from "forge-std/Vm.sol";
import {Craps} from "../../contracts/Craps.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

contract SysHarness is CrapsViews {}

/// @title The whole craps day, driven end to end on the SHIPPED contract, for its money.
///
/// @notice Everything else in the craps suite grades one rule. This one grades the LEDGER: it
///         opens real protocol days, seats real fields through the real doors, shuts every window
///         on the clock, settles every field through `resolveSlot`, and then reads what FLIP the
///         table actually destroyed and what it actually handed back.
///
/// @dev Three quantities, kept apart because they are not the same money:
///
///        burned     `IFlipCoin.burnCoin` — liquid FLIP destroyed at the door, at once.
///        credited   `ICoinflipStake.creditFlip` — a coinflip STAKE, not a mint. It becomes
///                   liquid FLIP only if its holder later cashes out of that game, and the
///                   coinflip carries its own edge on the way.
///        minted     `IFlipCoin.mintForGame` — liquid FLIP created. Craps is burn-only, so any
///                   nonzero figure here is a finding, not a measurement.
///
///      "Net burn" below is `burned - credited`: the conservative reading, which treats every
///      credit as if it were already liquid. The true liquid figure is strictly better.
contract CrapsSystemEconTest is CrapsPins {
    SysHarness internal craps;

    /// @dev Past any field these scenarios build, so one call settles a whole window.

    uint256 internal constant PERIODS = 7;

    // ── The board catalogue ─────────────────────────────────────────────────
    // Seven-chip strategy families, restated as real tickets. Every one obeys the
    // three-chips-a-leg cap and totals exactly seven, so every one is a legal entry.
    uint8 internal constant B_BLANK = 0;
    uint8 internal constant B_FAIR = 1; // true-odds Place 4/5/10 core
    uint8 internal constant B_SPREAD = 2; // fair spread over 4/5/9/10
    uint8 internal constant B_PASS = 3; // pass-heavy plus true-odds places
    uint8 internal constant B_DONT = 4; // don't-heavy plus true-odds places
    uint8 internal constant B_HARD = 5; // hardways plus one true-odds place
    uint8 internal constant B_MIXED = 6; // the mixed light board

    function _board(uint8 k) internal pure returns (Craps.Bets memory b) {
        if (k == B_FAIR) {
            b.place4 = 3;
            b.place5 = 1;
            b.place10 = 3;
        } else if (k == B_SPREAD) {
            b.place4 = 2;
            b.place5 = 2;
            b.place9 = 2;
            b.place10 = 1;
        } else if (k == B_PASS) {
            b.passLine = 3;
            b.place4 = 3;
            b.place10 = 1;
        } else if (k == B_DONT) {
            b.dontPass = 3;
            b.place4 = 3;
            b.place10 = 1;
        } else if (k == B_HARD) {
            b.place4 = 1;
            b.hard4 = 3;
            b.hard8 = 3;
        } else if (k == B_MIXED) {
            b.passLine = 2;
            b.place6 = 2;
            b.place8 = 2;
            b.hard4 = 1;
        }
        // B_BLANK names nothing: the dice place all ten.
    }

    /// @dev The same board in the packed form `setVaultBoard` takes — three bits a leg, board
    ///      order, don't pass at bit 27.
    function _packed(uint8 k) internal pure returns (uint32) {
        Craps.Bets memory b = _board(k);
        return uint32(
            uint256(b.passLine) | (uint256(b.place4) << 3) | (uint256(b.place5) << 6) | (uint256(b.place6) << 9)
                | (uint256(b.place8) << 12) | (uint256(b.place9) << 15) | (uint256(b.place10) << 18)
                | (uint256(b.hard4) << 21) | (uint256(b.hard8) << 24) | (uint256(b.dontPass) << 27)
        );
    }

    // ── A circumstance ──────────────────────────────────────────────────────
    struct Field {
        uint16 players; // ordinary player seats, on top of the two protocol bodies
        uint8 board; // what every one of them plays
        uint16 highSeats; // how many of those take the day's high multiple instead
        uint256 standing; // the activity score every player carries
        bool vaultOff; // stand the vault down
        bool vaultDark; // give the vault the don't-pass board
        bool starveBodies; // refuse the bodies' burn, so they fall through to the comp path
        // CHERRY-PICKING. Zero takes the whole day through the day lane. Nonzero takes windows
        // ONE AT A TIME and only where the schedule drew this goal multiple — the terms are
        // public before entry, so this is a door the contract actually leaves open.
        uint16 onlyGoalMult;
        uint8 onlyDepth; // and only at this bankroll depth; zero means any
    }

    struct Ledger {
        uint256 burned; // liquid FLIP destroyed at the door
        /// @dev PREPAID PRINCIPAL: the day bills the two protocol bodies paid with a banked PASS
        ///      rather than with FLIP. A pass is a day already bought — its FLIP was burned at the
        ///      lootbox door that awarded it — so for this table's own books it is a burn like any
        ///      other, and the identity below adds it to `burned`. Counting it as protocol money
        ///      instead would read twenty seeded days as a subsidy nobody paid for.
        uint256 passFunded;
        uint256 credited; // every coinflip credit the table handed back
        uint256 minted; // liquid FLIP created — must stay zero
        uint256 action; // bankroll the settled seats put up, all lanes
        uint256 highAction; // the high lane's share of it
        uint256 budget; // the daily main boost budgets this run opened on
        uint256 runCredit; // what the RUNS returned: the engine's own giveback
        uint256 potCredit; // what the main pots paid: bounties plus main boost
        uint256 laneCredit; // what a CONTESTED high lane paid its winner
        uint256 riderCredit; // a sole high rider's return, folded into its own run
        uint256 bounty; // the main bounties those pots were carrying
        uint256 lanePrincipal; // the EXTRA bounties a contested lane pays out — player money too
        uint256 daysRun;
        uint256 fields; // windows actually settled
        // Per-actor, so a circumstance can say WHO the money went to.
        uint256 housePot; // main pots the house won
        uint256 vaultPot; // main pots the vault won
        uint256 houseBurn;
        uint256 vaultBurn;
        uint256 houseCredit;
        uint256 vaultCredit;
        uint256 seats; // ordinary-equivalent seats in the field, bodies included
        uint256 bodyAction; // the protocol bodies' own share of the action
    }

    function setUp() public {
        _installPins();
        craps = new SysHarness();
        // Genesis is a Craps warm-up day; every fixture plays from genesis + 1.
        vm.warp(block.timestamp + 1 days);
        _setIndex(4);
    }

    // ── The driver ──────────────────────────────────────────────────────────

    function _dayStart() internal view returns (uint256) {
        return block.timestamp - ((block.timestamp - 82_620) % 1 days);
    }

    /// @dev The offset at which `period` stops taking bets. Restated from the schedule rather
    ///      than from the contract, so a driver that lands on it is landing on the published
    ///      clock time and not on whatever the contract happens to say.
    function _closeOf(uint256 period) internal view returns (uint256) {
        if (period + 1 == PERIODS) return 1 days - craps.EVENT_LEAD();
        uint256 base = period == 0 ? craps.BONUS_EVENT_CLOSE() : period * craps.BONUS_PERIOD();
        return base + craps.BONUS_CLOCK_ALIGN();
    }

    function _players(uint16 n, uint256 salt, uint256 standing) internal returns (address[] memory ps) {
        ps = new address[](n);
        for (uint256 i = 0; i < n; ++i) {
            ps[i] = address(uint160(uint256(keccak256(abi.encode("seat", salt, i)))));
            game.setScore(ps[i], standing);
        }
    }

    /// @dev Open a day, seat the field, shut all seven windows on their own clock times, settle
    ///      every field, and roll over. The whole protocol day, through production doors only.
    function _play(Field memory f, uint256 nDays, uint256 salt) internal returns (Ledger memory L) {
        // Land on the very start of a protocol day: the fixture clock sits an hour into one, past
        // the opener's close, and the day lane is sold in period 0 alone.
        vm.warp(_dayStart() + 1 days);

        address[] memory ps = _players(f.players, salt, f.standing);

        if (f.vaultOff) {
            // Read the sentinel BEFORE the prank: `vm.prank` binds the next call, and an
            // external constant read would consume it and leave `setVaultBoard` unpranked.
            uint32 off = craps.VAULT_BOARD_OFF();
            vm.prank(vaultOwner);
            craps.setVaultBoard(off);
        } else if (f.vaultDark) {
            vm.prank(vaultOwner);
            craps.setVaultBoard(_packed(B_DONT));
        }
        if (f.starveBodies) {
            flip.setBurnRefused(ContractAddresses.SDGNRS, true);
            flip.setBurnRefused(ContractAddresses.VAULT, true);
        }

        // ONE stack slot for the whole opening balance sheet: seven separate locals put this
        // frame over via-IR's limit, and every figure below is a plain before/after difference.
        uint256[7] memory snap = _snapshot();
        L.seats = uint256(f.players) + (f.vaultOff ? 1 : 2);

        Craps.Bets memory board = _board(f.board);

        for (uint256 d = 0; d < nDays; ++d) {
            uint24 day = craps.currentDayIndex();
            _setDailyWord(day, uint256(keccak256(abi.encode("day", salt, d))));

            // ONE BODY'S DAY BILL: every window's bankroll and its bounty, which is exactly what
            // `_seatBody` burns when FLIP is what pays. Readable as soon as the word is set.
            uint256 dayBill;
            for (uint256 p = 0; p < PERIODS; ++p) {
                (uint128 bankroll,,, uint256 bounty,,) = craps.bonusTermsFor(day, p);
                dayBill += uint256(bankroll) + bounty;
            }
            (uint256 hb,) = craps.passCreditsOf(ContractAddresses.SDGNRS);
            (uint256 vb,) = craps.passCreditsOf(ContractAddresses.VAULT);

            vm.prank(ContractAddresses.GAME);
            craps.openBonusDay();
            L.budget += craps.boostBudgetOf(day);
            // Whichever bodies paid out of the bank rather than out of FLIP.
            (uint256 ha,) = craps.passCreditsOf(ContractAddresses.SDGNRS);
            (uint256 va,) = craps.passCreditsOf(ContractAddresses.VAULT);
            L.passFunded += (hb - ha + vb - va) * dayBill;

            if (f.onlyGoalMult == 0) {
                uint256 hm = craps.highMultForDay(day);
                for (uint256 i = 0; i < ps.length; ++i) {
                    uint16 mult = i < f.highSeats ? uint16(hm) : 1;
                    vm.prank(ps[i]);
                    craps.enterBonusDay(board, mult);
                }
            } else {
                _seatSelectively(f, ps, board, day);
            }

            for (uint256 p = 0; p < PERIODS; ++p) {
                vm.warp(_dayStart() + _closeOf(p));
                uint64 slot = uint64(uint256(day) * craps.BONUS_SLOTS_PER_DAY() + p + 1);
                uint48 idx = craps.armBonusWindow(slot);
                _setIndex(idx);
                _setWord(idx, uint256(keccak256(abi.encode("table", salt, d, p))));
                _settleAndSplit(L, slot, day, p);
                ++L.fields;
            }

            // A protocol body takes a DAY seat, so its action is every window's bankroll. Summed
            // here so a report can hold the bodies' blank all-cell runs apart from the field's.
            uint256 dayBankroll;
            for (uint256 p = 0; p < PERIODS; ++p) {
                (uint128 bankroll,,,,,) = craps.bonusTermsFor(day, p);
                dayBankroll += bankroll;
            }
            L.bodyAction += dayBankroll * (f.vaultOff ? 1 : 2);
            L.action += craps.dayStaked(day);
            L.highAction += craps.highStakedOf(day);
            ++L.daysRun;
            vm.warp(_dayStart() + 1 days);
        }

        uint256[7] memory now_ = _snapshot();
        L.burned = now_[0] - snap[0];
        L.credited = now_[1] - snap[1];
        L.minted = now_[2] - snap[2];
        L.houseBurn = now_[3] - snap[3];
        L.vaultBurn = now_[4] - snap[4];
        L.houseCredit = now_[5] - snap[5];
        L.vaultCredit = now_[6] - snap[6];
        // Whatever the pots and the contested lane did not pay came home with the runs.
        L.runCredit = L.credited - L.potCredit - L.laneCredit;
    }

    /// @dev Seat the field ONLY at windows whose published terms match what the field is
    ///      hunting. `bonusTermsFor` is readable the moment the day opens and every window of
    ///      the day is still joinable then, so a field can read all seven and sit down at the
    ///      ones it likes. Nothing here is a cheat code: it is the ordinary per-window door.
    function _seatSelectively(Field memory f, address[] memory ps, Craps.Bets memory board, uint24 day)
        internal
    {
        // THE EVENT IS LEFT OUT. Its bankroll runs to sixty thousand against a routine window's
        // three hundred, so a handful of them would carry most of the field's action and the
        // measurement would be about those few runs rather than about the cell.
        for (uint256 p = 0; p + 1 < PERIODS; ++p) {
            (uint128 bankroll, uint128 goal, uint256 boardStake,,,) = craps.bonusTermsFor(day, p);
            if (bankroll == 0 || boardStake == 0) continue;
            if (goal / bankroll != f.onlyGoalMult) continue;
            // `boardStake` is the SEVEN chips a picking ticket posts, not the whole round, so the
            // round is `boardStake * 10 / 7` and the depth is the bankroll over that.
            if (f.onlyDepth != 0 && (uint256(bankroll) * 7) / (boardStake * 10) != f.onlyDepth) continue;
            for (uint256 i = 0; i < ps.length; ++i) {
                vm.prank(ps[i]);
                craps.enterBonusBattle(p, board, 1);
            }
        }
    }

    /// @dev The whole FLIP balance sheet in one read: totals first, then the two protocol
    ///      bodies' own burns and credits.
    function _snapshot() internal view returns (uint256[7] memory v) {
        v[0] = flip.totalBurned();
        v[1] = coinflip.totalCredited();
        v[2] = flip.totalMinted();
        v[3] = flip.burned(ContractAddresses.SDGNRS);
        v[4] = flip.burned(ContractAddresses.VAULT);
        v[5] = coinflip.staked(ContractAddresses.SDGNRS);
        v[6] = coinflip.staked(ContractAddresses.VAULT);
    }

    /// @dev Settle one window and split what it paid into the three lanes the events keep apart:
    ///      the main pot, a contested high lane, and a sole rider's own return. Everything the
    ///      batch credited that is not one of those is a RUN coming home.
    function _settleAndSplit(Ledger memory L, uint64 slot, uint24 day, uint256 period) internal {
        (bytes32 key,,,) = craps.bonusWindowOf(period);
        (,,, uint256 battleStake,,) = craps.bonusTermsFor(day, period);
        uint256 entrants = craps.battleOf(key).entrants;
        // The lane's principal has to be read BEFORE the walk: settlement stamps the sideboard
        // done, and a claimed lane is what the payment is drawn from.
        (uint32 heads,,,,) = craps.highFieldOf(key);
        uint256 laneStake = heads >= 2 ? heads * (craps.highMultOfSlot(slot) - 1) * battleStake : 0;

        vm.recordLogs();
        craps.resolveSlot(slot, WHOLE_FIELD);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        PaidOut[] memory pots = _potsIn(logs);
        for (uint256 i = 0; i < pots.length; ++i) {
            L.potCredit += pots[i].amount;
            L.bounty += battleStake * entrants;
            if (pots[i].player == ContractAddresses.SDGNRS) L.housePot += pots[i].amount;
            else if (pots[i].player == ContractAddresses.VAULT) L.vaultPot += pots[i].amount;
        }
        PaidOut[] memory lane = _lanePaymentsIn(logs, false);
        for (uint256 i = 0; i < lane.length; ++i) {
            L.laneCredit += lane[i].amount;
            L.lanePrincipal += laneStake;
        }
        PaidOut[] memory riders = _lanePaymentsIn(logs, true);
        for (uint256 i = 0; i < riders.length; ++i) L.riderCredit += riders[i].amount;
    }

    // ── Reporting ───────────────────────────────────────────────────────────

    /// @dev Basis points of `part` in `whole`, guarding the empty case.
    function _bps(uint256 part, uint256 whole) internal pure returns (uint256) {
        return whole == 0 ? 0 : (part * 10_000) / whole;
    }

    function _report(string memory name, Ledger memory L) internal {
        uint256 dn = L.daysRun == 0 ? 1 : L.daysRun;
        emit log("");
        emit log(name);
        emit log_named_uint("  days / fields        ", L.daysRun * 1_000_000 + L.fields);
        emit log_named_uint("  action FLIP/day      ", L.action / dn / 1 ether);
        emit log_named_uint("  high action FLIP/day ", L.highAction / dn / 1 ether);
        emit log_named_uint("  BURNED FLIP/day      ", L.burned / dn / 1 ether);
        emit log_named_uint("  CREDITED FLIP/day    ", L.credited / dn / 1 ether);
        emit log_named_int(
            "  NET BURN FLIP/day    ", (int256(L.burned) - int256(L.credited)) / int256(dn) / 1 ether
        );
        emit log_named_uint("  -- run credit /day   ", L.runCredit / dn / 1 ether);
        emit log_named_uint("  -- pot credit /day   ", L.potCredit / dn / 1 ether);
        emit log_named_uint("  ---- of which bounty ", L.bounty / dn / 1 ether);
        emit log_named_uint(
            "  ---- of which BOOST  ", (L.potCredit > L.bounty ? L.potCredit - L.bounty : 0) / dn / 1 ether
        );
        emit log_named_uint("  -- lane credit /day  ", L.laneCredit / dn / 1 ether);
        emit log_named_uint("  ---- of which stake  ", L.lanePrincipal / dn / 1 ether);
        emit log_named_uint("  -- rider (in run)/day", L.riderCredit / dn / 1 ether);
        emit log_named_uint("  budget quoted /day   ", L.budget / dn / 1 ether);
        emit log_named_uint("  ENGINE EDGE      bps ", _bps(L.action > L.runCredit ? L.action - L.runCredit : 0, L.action));
        emit log_named_uint("  body action /day     ", L.bodyAction / dn / 1 ether);
        emit log_named_int("  house run credit /day", int256(L.houseCredit - L.housePot) / int256(dn) / 1 ether);
        // The FIELD's own edge, with the protocol bodies' blank all-cell runs taken back out.
        // The bodies play every window on a blank board, so leaving them in measures a different
        // board on a different set of terms.
        if (L.action > L.bodyAction) {
            uint256 pAct = L.action - L.bodyAction;
            uint256 pRun = L.runCredit - (L.houseCredit - L.housePot) - (L.vaultCredit - L.vaultPot);
            emit log_named_uint("  player action /day   ", pAct / dn / 1 ether);
            emit log_named_uint("  PLAYER-ONLY EDGE bps ", _bps(pAct > pRun ? pAct - pRun : 0, pAct));
        }
        emit log_named_uint("  budget rate      bps ", _bps(L.budget, L.action));
        emit log_named_uint("  net burn / burn  bps ", _bps(L.burned > L.credited ? L.burned - L.credited : 0, L.burned));
        emit log_named_uint("  net burn / action bps", _bps(L.burned > L.credited ? L.burned - L.credited : 0, L.action));
        emit log_named_uint("  liquid FLIP minted   ", L.minted);
    }

    /// @dev Per-actor ROI: what a group put in at the door against everything it got back.
    function _actors(Ledger memory L) internal {
        uint256 pb = L.burned - L.houseBurn - L.vaultBurn;
        uint256 pc = L.credited - L.houseCredit - L.vaultCredit;
        emit log_named_int("  house ROI        bps ", _roi(L.houseBurn, L.houseCredit));
        emit log_named_int("  vault ROI        bps ", _roi(L.vaultBurn, L.vaultCredit));
        emit log_named_int("  players ROI      bps ", _roi(pb, pc));
        emit log_named_uint("  house pot share  bps ", _bps(L.housePot, L.potCredit));
        emit log_named_uint("  vault pot share  bps ", _bps(L.vaultPot, L.potCredit));
    }

    function _roi(uint256 burnt, uint256 back) internal pure returns (int256) {
        // A comped seat burned nothing, so its return has no denominator. Reported as the
        // sentinel rather than as a division, since "infinite ROI" is the finding.
        if (burnt == 0) return back == 0 ? int256(0) : int256(-1_000_000);
        return (int256(back) - int256(burnt)) * 10_000 / int256(burnt);
    }

    function _fair(uint16 n) internal pure returns (Field memory f) {
        f.players = n;
        f.board = B_FAIR;
        f.standing = 1000;
    }

    // ════════════════════════════════════════════════════════════════════════
    // A. THE COLD TABLE — what the protocol pays to keep a day running at all.
    // ════════════════════════════════════════════════════════════════════════

    /// @notice Nobody at all: the two protocol bodies alone, both paying cash for their seats.
    function test_A1_coldTableBothBodiesCashFunded() public {
        Field memory f;
        Ledger memory L = _play(f, 800, 0xA1);
        _report("A1  cold table: house + vault, cash funded, blank boards", L);
        _actors(L);
        assertEq(L.minted, 0, "craps minted liquid FLIP");
    }

    /// @notice The vault stands down. One blank house body, alone, winning every pot it plays for.
    function test_A2_coldTableVaultStoodDown() public {
        Field memory f;
        f.vaultOff = true;
        Ledger memory L = _play(f, 800, 0xA2);
        _report("A2  cold table: vault OFF, house alone", L);
        _actors(L);
    }

    /// @notice Neither body can fund its seat. The house is comped in anyway; the vault is not.
    function test_A3_coldTableBodiesStarved() public {
        Field memory f;
        f.starveBodies = true;
        Ledger memory L = _play(f, 800, 0xA3);
        _report("A3  cold table: both bodies' burn REFUSED (comp path)", L);
        _actors(L);
    }

    /// @notice The vault takes the dark board against a blank house.
    function test_A4_coldTableDarkVault() public {
        Field memory f;
        f.vaultDark = true;
        Ledger memory L = _play(f, 800, 0xA4);
        _report("A4  cold table: house blank, vault DON'T PASS", L);
        _actors(L);
    }

    // ════════════════════════════════════════════════════════════════════════
    // B. THE THIN TABLE — one player against the bodies, and the standing gate.
    // ════════════════════════════════════════════════════════════════════════

    function test_B1_oneEstablishedPlayer() public {
        Ledger memory L = _play(_fair(1), 800, 0xB1);
        _report("B1  thin: 1 fair-core player, FULL standing, + 2 bodies", L);
        _actors(L);
    }

    /// @notice The same seat with no activity history at all. House money is rationed to nothing;
    ///         bounties are not rationed and still pay.
    function test_B2_oneScoreZeroPlayer() public {
        Field memory f = _fair(1);
        f.standing = 0;
        Ledger memory L = _play(f, 800, 0xB2);
        _report("B2  thin: 1 fair-core player, ZERO standing, + 2 bodies", L);
        _actors(L);
    }

    function test_B3_threeEstablishedPlayers() public {
        Ledger memory L = _play(_fair(3), 400, 0xB3);
        _report("B3  thin: 3 fair-core players + 2 bodies", L);
        _actors(L);
    }

    // ════════════════════════════════════════════════════════════════════════
    // C. THE HEALTHY TABLE — a full field, one board at a time.
    // ════════════════════════════════════════════════════════════════════════

    function _healthy(uint8 board, string memory name, uint256 salt) internal {
        Field memory f;
        f.players = 30;
        f.board = board;
        f.standing = 1000;
        Ledger memory L = _play(f, 120, salt);
        _report(name, L);
        _actors(L);
        assertEq(L.minted, 0, "craps minted liquid FLIP");
    }

    function test_C1_thirtyBlank() public {
        _healthy(B_BLANK, "C1  healthy: 30 BLANK players + 2 bodies", 0xC1);
    }

    function test_C2_thirtyFairCore() public {
        _healthy(B_FAIR, "C2  healthy: 30 FAIR-CORE players + 2 bodies", 0xC2);
    }

    function test_C3_thirtySpread() public {
        _healthy(B_SPREAD, "C3  healthy: 30 FAIR-SPREAD players + 2 bodies", 0xC3);
    }

    function test_C4_thirtyPass() public {
        _healthy(B_PASS, "C4  healthy: 30 PASS-LINE players + 2 bodies", 0xC4);
    }

    function test_C5_thirtyDontPass() public {
        _healthy(B_DONT, "C5  healthy: 30 DON'T-PASS players + 2 bodies", 0xC5);
    }

    function test_C6_thirtyHardways() public {
        _healthy(B_HARD, "C6  healthy: 30 HARDWAY players + 2 bodies", 0xC6);
    }

    function test_C7_thirtyMixed() public {
        _healthy(B_MIXED, "C7  healthy: 30 MIXED-LIGHT players + 2 bodies", 0xC7);
    }

    // ════════════════════════════════════════════════════════════════════════
    // D. GOVERNANCE — the one board the protocol itself gets to choose.
    // ════════════════════════════════════════════════════════════════════════

    function test_D1_darkVaultAgainstAFullField() public {
        Field memory f = _fair(30);
        f.vaultDark = true;
        Ledger memory L = _play(f, 120, 0xD1);
        _report("D1  30 fair-core players, house blank, vault DON'T PASS", L);
        _actors(L);
    }

    // ════════════════════════════════════════════════════════════════════════
    // E. THE HIGH LANE.
    // ════════════════════════════════════════════════════════════════════════

    function test_E1_oneHighRoller() public {
        Field memory f = _fair(21);
        f.highSeats = 1;
        Ledger memory L = _play(f, 120, 0xE1);
        _report("E1  20 fair-core + 2 bodies + ONE high roller (sole rider)", L);
        _actors(L);
    }

    function test_E2_twoHighRollers() public {
        Field memory f = _fair(22);
        f.highSeats = 2;
        Ledger memory L = _play(f, 120, 0xE2);
        _report("E2  20 fair-core + 2 bodies + TWO high rollers (contested)", L);
        _actors(L);
    }

    function test_E3_fiveHighRollers() public {
        Field memory f = _fair(25);
        f.highSeats = 5;
        Ledger memory L = _play(f, 120, 0xE3);
        _report("E3  20 fair-core + 2 bodies + FIVE high rollers", L);
        _actors(L);
    }

    // ════════════════════════════════════════════════════════════════════════
    // F. THE ACCOUNTING IDENTITY — what net emission actually reduces to.
    // ════════════════════════════════════════════════════════════════════════

    /// @notice THE ONE THAT EXPLAINS EVERY OTHER NUMBER HERE, and it is exact rather than
    ///         sampled. Across any field, on any board, in any lane:
    ///
    ///           burned          = action + bounties           (the door takes both)
    ///           credited        = run credit + bounties + boost + lane principal
    ///           => net burn     = (action - run credit) - boost - lane boost
    ///                           = ENGINE RETENTION - HOUSE MONEY PAID
    ///
    ///         The bounties cancel: every one of them is burned by a seat and credited to a
    ///         winner. So the table's net FLIP position is engine retention minus subsidy and
    ///         NOTHING else — no term in it depends on who won, only on what the dice kept and
    ///         what the protocol chose to give back.
    ///
    ///         Asserted here to the WEI on a field carrying every lane at once.
    function test_F1_netBurnIsEngineRetentionMinusHouseMoney() public {
        Field memory f = _fair(12);
        f.highSeats = 2;
        f.vaultDark = true;
        Ledger memory L = _play(f, 40, 0xF1);

        // The bounty leg of the pots is a pure transfer, so it must cancel exactly.
        //
        // A PASS-FUNDED SEAT IS A FLIP-FUNDED SEAT. Both bodies are banked twenty day passes at
        // deployment and the day lane spends the bank before it burns, so the opening days are
        // paid for with passes — days that were bought at the lootbox door, whose FLIP was burned
        // there. Adding that prepaid principal here is what makes the identity independent of
        // which of the two funded any given seat.
        int256 net = int256(L.burned + L.passFunded) - int256(L.credited);
        int256 retention = int256(L.action) - int256(L.runCredit);
        // HOUSE MONEY IS THE BOOSTS ALONE. Everything else in a pot — the main bounty every seat
        // posted, and the extra bounties a contested lane plays for — was burned by a seat and
        // credited to a seat, so it cancels out of the protocol's own position.
        int256 houseMoney =
            int256(L.potCredit) - int256(L.bounty) + int256(L.laneCredit) - int256(L.lanePrincipal);

        emit log_named_uint("prepaid principal", L.passFunded);
        emit log_named_int("net burn        ", net);
        emit log_named_int("engine retention", retention);
        emit log_named_int("house money paid", houseMoney);
        emit log_named_int("identity residue", net - (retention - houseMoney));

        // The lane's PRINCIPAL is player-funded too — `heads * (highMult - 1) * stake` — so it
        // sits inside `houseMoney` above alongside the lane boost. Both are burned by high seats
        // and credited to one of them, so the identity closes on the whole field's action.
        assertEq(net, retention - houseMoney, "net burn is not retention minus house money");
        assertEq(L.minted, 0, "craps minted liquid FLIP");
    }

    /// @notice THE EQUILIBRIUM, stated as the arithmetic that produces it. The schedule allocates
    ///         `50,000 FLIP + 12% of action` every opened day. The 50,000 is protocol money
    ///         whether or not the table earned it, so a day is self-funding only once engine
    ///         retention above the 12% covers it.
    ///
    ///         THE SPLIT DOES NOT MOVE THIS CURVE. Half the allocation is the ladder the day's
    ///         windows pay out immediately and half is banked in the progressive, but a wei banked
    ///         is a wei allocated: the progressive is a liability the moment it is funded, and its
    ///         later payout releases that liability rather than issuing again. So the emission
    ///         this grades is the WHOLE allocation, split or not.
    ///
    ///         At the conservative 16% whole-run take and the ~15,600 FLIP of bankroll action an
    ///         ordinary daily ticket puts through, each ticket leaves `15,600 * 4% = 624` FLIP
    ///         behind and the day nets `624 * tickets - 50,000`. This is a division, not a
    ///         sample: it fixes the curve the simulator and the docs are held to.
    function test_F2_theBaseSubsidySetsABreakEvenTicketCount() public {
        uint256 baseFlip = craps.BASE_MAIN_BUDGET() / 1 ether;
        uint256 rateBps = craps.BOOST_ACTION_BPS();
        emit log_named_uint("base subsidy FLIP/day             ", baseFlip);
        emit log_named_uint("linear rate bps of action         ", rateBps);

        // The policy calibration: a conservative whole-run take, and one ordinary ticket's action.
        uint256 takeBps = 1600;
        uint256 ticketAction = 15_600;
        uint256 residualPerTicket = ticketAction * (takeBps - rateBps) / 10_000;
        emit log_named_uint("residual burn FLIP/ticket at 16%  ", residualPerTicket);
        assertEq(residualPerTicket, 624, "the per-ticket residual moved off 624 FLIP");

        // The curve, at the five counts the specification names.
        uint16[5] memory counts = [uint16(0), 2, 16, 40, 41];
        for (uint256 i = 0; i < 5; ++i) {
            uint256 action = uint256(counts[i]) * ticketAction;
            uint256 retention = action * takeBps / 10_000;
            uint256 bonus = baseFlip + action * rateBps / 10_000;
            emit log_named_uint("  tickets                        ", counts[i]);
            emit log_named_uint("    action FLIP                  ", action);
            emit log_named_uint("    engine take at 16% FLIP      ", retention);
            emit log_named_uint("    allocation 50k + 12% FLIP    ", bonus);
            emit log_named_int("    NET (positive = issuance)    ", int256(bonus) - int256(retention));
        }

        // The three the specification pins by name.
        assertEq(baseFlip, 50_000, "a zero-ticket day does not allocate exactly the base");
        assertEq(
            int256(baseFlip + 32 * ticketAction * rateBps / 10_000)
                - int256(32 * ticketAction * takeBps / 10_000),
            int256(uint256(50_000 - 32 * 624)),
            "the thirty-two-ticket day is not 50,000 - 32 * 624"
        );
        assertEq(baseFlip / residualPerTicket, 80, "break-even is not about eighty tickets");
        // And it is a CROSSING, not a floor: one more ticket puts the day into net burn.
        assertGt(81 * residualPerTicket, baseFlip, "the eighty-first ticket did not cross into burn");
        assertLt(80 * residualPerTicket, baseFlip, "the eightieth ticket was already in burn");

        // AND THE SPLIT CONSERVES IT. Whatever the raw allocation is, the ladder half plus the
        // progressive contribution is that figure exactly — so nothing above is an accounting of
        // only half the emission.
        (uint256 ladder, uint256 contribution) = craps.splitMainBudget(craps.BASE_MAIN_BUDGET());
        assertEq(ladder + contribution, craps.BASE_MAIN_BUDGET(), "the split did not conserve the allocation");
        assertEq(ladder, 25_000 ether, "a cold day's ladder is not 25,000 FLIP");
        assertEq(contribution, 25_000 ether, "a cold day's progressive contribution is not 25,000 FLIP");
    }

    /// @notice Craps is BURN-ONLY. Every scenario above asserts it; this one states it as the
    ///         standalone invariant, across a mixed field with every lane live.
    function test_F3_theTableNeverMintsLiquidFlip() public {
        Field memory f = _fair(12);
        f.highSeats = 2;
        f.vaultDark = true;
        Ledger memory L = _play(f, 60, 0xF3);
        _report("F3  mixed field, every lane live", L);
        _actors(L);
        assertEq(L.minted, 0, "craps minted liquid FLIP");
        assertEq(flip.totalMinted(), 0, "craps minted liquid FLIP anywhere");
    }

    // ════════════════════════════════════════════════════════════════════════
    // G. HOW NOISY IS ANY OF THIS? — the error bar, measured rather than assumed.
    // ════════════════════════════════════════════════════════════════════════

    /// @notice A run can return up to fifty times its bankroll, so the mean of a field's returns
    ///         converges slowly and every sampled figure in this suite carries a real error bar.
    ///         This measures it: the SAME field, replayed against independent word streams. What
    ///         is printed is the spread, and it is what every other number here must be read
    ///         against. It is also a PRODUCT fact, not only a measurement one — a live table's
    ///         daily net position swings by the same amount.
    function test_G1_theSpreadAcrossIndependentWordStreams() public {
        emit log("G1  same 30-seat fair-core field, 10 independent word streams, 30 days each");
        int256 lo = type(int256).max;
        int256 hi = type(int256).min;
        int256 sum;
        int256 netLo = type(int256).max;
        int256 netHi = type(int256).min;
        uint256 n = 10;
        for (uint256 r = 0; r < n; ++r) {
            Ledger memory L = _play(_fair(30), 30, 0x610000 + r);
            // SIGNED on purpose: a replicate in which the field's runs came home for more than
            // they staked is not an error, it is the tail this test exists to show.
            int256 edge = (int256(L.action) - int256(L.runCredit)) * 10_000 / int256(L.action);
            int256 net = (int256(L.burned) - int256(L.credited)) / int256(L.daysRun) / 1 ether;
            emit log_named_int("  replicate engine edge bps", edge);
            emit log_named_int("  replicate net burn/day  ", net);
            if (edge < lo) lo = edge;
            if (edge > hi) hi = edge;
            if (net < netLo) netLo = net;
            if (net > netHi) netHi = net;
            sum += edge;
        }
        emit log_named_int("  MEAN engine edge bps    ", sum / int256(n));
        emit log_named_int("  MIN  engine edge bps    ", lo);
        emit log_named_int("  MAX  engine edge bps    ", hi);
        emit log_named_int("  MIN  net burn FLIP/day  ", netLo);
        emit log_named_int("  MAX  net burn FLIP/day  ", netHi);
    }

    // ════════════════════════════════════════════════════════════════════════
    // H. CHERRY-PICKING — the field reads the schedule before it sits down.
    // ════════════════════════════════════════════════════════════════════════

    /// @notice `bonusTermsFor` is public and every window of a day is joinable the moment the day
    ///         opens, so nothing stops a field from reading all seven and entering only the ones
    ///         whose terms it likes. Depth and goal are drawn independently — three depths, four
    ///         goals — so one routine window in twelve is the shallowest, lowest-target cell,
    ///         which is also the cell in which a run is least likely to bust and therefore the
    ///         one that gives the LEAST back to the deletion the subsidy is funded by.
    ///
    ///         This drives that field on the real contract and reports what it does to the
    ///         ledger, against the same field taking the whole day blind.
    function test_H1_aFieldThatOnlyTakesTheCheapestCell() public {
        Field memory f = _fair(20);
        f.vaultOff = true;
        f.onlyGoalMult = 5;
        f.onlyDepth = 2;
        Ledger memory L = _play(f, 1600, 0x81);
        _report("H1  20 fair-core seats, ONLY depth-2 / goal-5x windows", L);
        emit log_named_uint("  linear give-back bps  ", craps.BOOST_ACTION_BPS());
        assertEq(L.minted, 0, "craps minted liquid FLIP");
    }

    /// @notice The control: the SAME seats, the same board, taking every window the day offers.
    function test_H2_theSameFieldTakingTheWholeDay() public {
        Field memory f = _fair(20);
        f.vaultOff = true;
        Ledger memory L = _play(f, 300, 0x82);
        _report("H2  20 fair-core seats, the WHOLE day (control for H1)", L);
        assertEq(L.minted, 0, "craps minted liquid FLIP");
    }

    /// @dev Diagnostic: what the selector actually selected, and what the schedule offered.
    function test_H0_whatTheSelectorSees() public {
        vm.warp(_dayStart() + 1 days);
        uint256 goalFive;
        uint256 otherGoals;
        uint256 depthFive;
        uint256 otherDepths;
        uint256 windows;
        for (uint256 d = 0; d < 200; ++d) {
            uint24 day = craps.currentDayIndex();
            _setDailyWord(day, uint256(keccak256(abi.encode("day", uint256(0x81), d))));
            vm.prank(ContractAddresses.GAME);
            craps.openBonusDay();
            for (uint256 p = 0; p < PERIODS; ++p) {
                (uint128 bankroll, uint128 goal, uint256 boardStake,,,) = craps.bonusTermsFor(day, p);
                ++windows;
                uint256 gm = goal / bankroll;
                uint256 dep = bankroll / ((boardStake * 10) / 7);
                if (gm == 5) ++goalFive;
                else ++otherGoals;
                if (dep == 5) ++depthFive;
                else ++otherDepths;
            }
            vm.warp(_dayStart() + 1 days);
        }
        emit log_named_uint("windows seen", windows);
        emit log_named_uint("goal 5x    ", goalFive);
        emit log_named_uint("other goals", otherGoals);
        emit log_named_uint("depth 5    ", depthFive);
        emit log_named_uint("other depth", otherDepths);
        assertEq(goalFive, windows, "the main schedule offered a non-5x goal");
        assertEq(depthFive, windows, "the main schedule offered a non-5x depth");
    }
}
