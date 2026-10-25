// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {DegenerusGameLens} from "../../../contracts/DegenerusGameLens.sol";
import {DegenerusGameStorage} from "../../../contracts/storage/DegenerusGameStorage.sol";
import {DegenerusVault} from "../../../contracts/DegenerusVault.sol";
import {sDGNRS} from "../../../contracts/sDGNRS.sol";
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";
import {IStETH} from "../../../contracts/interfaces/IStETH.sol";
import {PriceLookupLib} from "../../../contracts/libraries/PriceLookupLib.sol";
import {GameTimeLib} from "../../../contracts/libraries/GameTimeLib.sol";
import {SolvencyObligations} from "../helpers/SolvencyObligations.sol";
import {TicketQueueStorage} from "../helpers/TicketQueueStorage.sol";
import {GameSlots} from "../../helpers/GameSlots.sol";

/// @dev Etched over the Game: back claimable credits, seed far-future collateral, keep the daily
///      index current, and enter a due level arming its settlement as `prepareRequestBoundary` does.
///      `seize` runs the production worker in the Game's context.
contract LoanAccountingSeeder is DegenerusGameStorage {
    function credit(uint32 id, uint128 amount) external {
        balancesPacked[id] += amount;
        claimablePool += amount;
    }

    function seedLevel(uint32 id, uint24 lvl, uint32 entries) external {
        if (lvl <= _mintCeiling()) revert E();
        _queueEntries(id, lvl, entries, false);
    }

    function sync() public {
        uint24 day = _wallDay();
        _recordDailyRng(day - 1, 123456);
        dailyIdx = day;
        dailyComplete = true;
        lastDailyCompletedAt = uint48(block.timestamp);
        lastDailyRequestWallDay = _wallDay();
    }

    function startPhase(bool jackpot) public {
        sync();
        purchaseStartDay = dailyIdx;
        jackpotPhaseFlag = jackpot;
    }

    function enterDue(uint24 due, bool jackpot) external {
        startPhase(jackpot);
        level = due;
        // The skipped levels' ticket queues would have drained by now: clear their owners'
        // pending lanes and free their parity roots.
        uint24 active = _activeTicketLevel();
        for (uint24 lvl = 1; lvl < active; ++lvl) {
            _drain(lvl);
            _drain(lvl | TICKET_SLOT_BIT);
        }
        if (_loansDueCount[due] != 0) {
            _setLoansDuePending(true);
            loanSeizeCursor = 0;
        }
    }

    function _drain(uint24 rk) private {
        uint256 lvl = rk & 0x3fffff;
        uint256 len;
        uint256 base;
        {
            uint24 physical = _ticketQueueStorageKey(rk);
            uint256 header;
            assembly ("memory-safe") {
                mstore(0, physical)
                mstore(32, ticketQueue.slot)
                let slot := keccak256(0, 64)
                header := sload(slot)
                mstore(0, slot)
                base := keccak256(0, 32)
            }
            uint256 occupying = (header >> 32) & 0xffffff;
            if (occupying == 0) occupying = physical & 0x7f;
            if (occupying != lvl) return;
            len = header & 0xffffffff;
        }
        uint256 tagShift = 168 + (lvl & 1) * 24;
        uint256 clear = ~((((uint256(1) << 84) - 1) << ((lvl & 1) * 84)) | (uint256(0xffffff) << tagShift));
        for (uint256 i; i < len; ++i) {
            uint256 word;
            assembly ("memory-safe") { word := sload(add(base, shr(3, i))) }
            uint32 id = uint32(word >> ((i & 7) * 32));
            uint256 w = ticketPending[id];
            if ((w >> tagShift) & 0xffffff == lvl) ticketPending[id] = w & clear;
        }
        _releaseTicketQueue(rk);
    }

    function pending() external view returns (bool) {
        return _loansDuePending();
    }

    function seize() external {
        (bool ok, bytes memory data) = ContractAddresses.GAME_ADVANCE_MODULE.delegatecall(
            abi.encodeWithSignature("runLoanSeizureWork(uint256)", gasleft())
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
    }
}

/// @notice Drives account loans through borrow, early repayment, funding steers, due-level
///         settlement (auto-repay or seizure), sweeps and claims, against a ledger computed from
///         docs/ACCOUNT-LOANS.md. Expected principals, owed amounts, lenders, ticket parts, outcomes
///         and owners come from the spec formulas and the handler's own collateral record, never
///         from the contract's loan views. The first PLAN.length steps of every run follow a fixed
///         op order (fuzzed arguments) that forces a borrow, a late-window borrow, a repayment, an
///         auto-repayment and a seizure, so no run passes without every transition.
contract LoanAccountingHandler is Test {
    DegenerusGame public immutable game;
    DegenerusGameLens public immutable lens;
    sDGNRS public immutable sdgnrsToken;
    DegenerusVault public immutable vault;
    address private immutable seeder;
    bytes private gameRuntime;

    uint32 internal constant VAULT_ID = 1;
    uint32 internal constant SDGNRS_ID = 2;
    uint256 internal constant MIN_PRINCIPAL = 0.05 ether;
    uint256 internal constant SDGNRS_RESERVE = 1 ether;
    uint256 internal constant VAULT_FLOOR = 1 ether;
    uint256 internal constant MAX_FAMILY = 6;
    uint256 internal constant TICKET_AFTER_DAYS = 20;
    uint256 internal constant MAX_DAYS_IN_PHASE = 28; // below the 30-day purchase deadline
    uint24 internal constant MAX_LEVEL = 100; // collateral stays inside one far-future ring cycle
    uint8 internal constant ACTION_SEIZE_LOANS = 19;
    uint256 internal constant N_ACTORS = 3;

    uint8 internal constant OP_SEED = 0;
    uint8 internal constant OP_BORROW = 1;
    uint8 internal constant OP_REPAY = 2;
    uint8 internal constant OP_STEER = 3;
    uint8 internal constant OP_ADVANCE = 4;
    uint8 internal constant OP_SWEEP = 5;
    uint8 internal constant OP_CLAIM = 6;
    uint8 internal constant OP_SMURF = 7;
    uint8 internal constant OP_WARP = 8;
    uint8 internal constant OP_MAIN = 9;
    uint256 public constant N_OPS = 10;
    /// @dev Random-phase weights: index = seed % 14.
    bytes internal constant WEIGHTED = hex"0001010102030304040506070809";
    /// @dev Forced opening: seed, cash borrow, warp to day 20 exactly (still cash), warp past it,
    ///      two late borrows, repay, cover one loan, then settle every remaining due level.
    bytes internal constant PLAN = hex"000108010801010203040404";

    struct Acct {
        uint32 id;
        uint8 actor;
        bool smurf;
        uint16 mainIdx;
        uint8 smurfs; // lifetime smurfs created (mains)
        uint32 seizedTo; // lender that took this account by its own default
    }

    struct Loan {
        uint256 principal;
        uint256 ticketWei;
        uint32 lender;
        uint24 start;
        uint24 due;
        bool open;
    }

    struct Bal {
        uint256 claim;
        uint256 afk;
    }

    address[N_ACTORS] public actors;
    uint256[N_ACTORS] internal liveMain; // acct index + 1, zero once seized

    Acct[] internal accts;
    mapping(uint256 => Loan) internal loans;
    mapping(uint32 => uint256) internal idxOf; // id => index + 1
    mapping(uint256 => mapping(uint256 => uint256)) internal collateral; // index => level => entries
    mapping(uint24 => uint32[]) internal dueList; // model of _loansDue, history once entered
    uint24[] internal dueLevels;
    mapping(uint24 => bool) internal dueSeen;

    uint24 internal purchaseStart;
    bool internal jackpotPhase;

    // Lender ledger: funds = claimable (with its sentinel) + AFKing.
    mapping(uint32 => uint256) public lenderBase;
    mapping(uint32 => uint256) public receipts;
    mapping(uint32 => uint256) public lent;
    mapping(uint32 => uint256) public swept;

    // Progress.
    uint256 public calls;
    uint256[N_OPS] public opCalls;
    uint256 public ghost_borrows;
    uint256 public ghost_ticketBorrows;
    uint256 public ghost_day20Borrows; // purchase phase, exactly 20 days in: still all cash
    uint256 public ghost_jackpotBorrows;
    uint256 public ghost_vaultLoans;
    uint256 public ghost_smurfLoans;
    uint256 public ghost_repays;
    uint256 public ghost_repaysFromClaimable;
    uint256 public ghost_autoRepays;
    uint256 public ghost_seizures;
    uint256 public ghost_mainSeizures;
    uint256 public ghost_orphanSeizures;
    uint256 public ghost_chunkedSettles;
    uint256 public ghost_sweeps;
    uint256 public ghost_claims;
    uint256 public ghost_gateRejects;
    uint256 public ghost_closed;

    // Violations per invariant (1..5) with the first message of each.
    uint256[6] public vio;
    string[6] internal firstVio;

    constructor(DegenerusGame game_, sDGNRS sdgnrs_, DegenerusVault vault_) {
        game = game_;
        sdgnrsToken = sdgnrs_;
        vault = vault_;
        lens = new DegenerusGameLens();
        seeder = address(new LoanAccountingSeeder());
        gameRuntime = address(game_).code;
    }

    /// @dev Lenders, actors and the opening families; the ledger baseline is taken last.
    function init() external {
        require(accts.length == 0);
        _credit(SDGNRS_ID, 8 ether); // runs dry within a few loans so the Vault lends too
        _credit(VAULT_ID, 40 ether);
        vm.prank(ContractAddresses.OWNER_GOVERNANCE);
        vault.setLiquidationBuyFallback(true, VAULT_FLOOR);
        _etch();
        LoanAccountingSeeder(address(game)).startPhase(false);
        _unetch();
        purchaseStart = GameTimeLib.gameDayIndex();
        for (uint256 i; i < N_ACTORS; ++i) {
            actors[i] = address(uint160(0x10A40000 + i));
            _newMain(i);
        }
        _createSmurf(0);
        _createSmurf(0);
        _createSmurf(1);
        for (uint32 l = VAULT_ID; l <= SDGNRS_ID; ++l) lenderBase[l] = _funds(l);
    }

    // ------------------------------------------------------------------ dispatcher

    function step(uint256 opSeed, uint256 a, uint256 b) external {
        bool plan = calls < PLAN.length;
        uint8 op = plan ? uint8(PLAN[calls]) : uint8(WEIGHTED[opSeed % WEIGHTED.length]);
        ++calls;
        ++opCalls[op];
        int256 surplusBefore = _surplus();
        if (op == OP_SEED) _seed(a, b);
        else if (op == OP_BORROW) _borrow(a, b, plan);
        else if (op == OP_REPAY) _repay(a, b, plan);
        else if (op == OP_STEER) _steer(a, b, plan);
        else if (op == OP_ADVANCE) _advance(a, b, plan);
        else if (op == OP_SWEEP) _sweep(a, b);
        else if (op == OP_CLAIM) _claim(a, b);
        else if (op == OP_SMURF) _createSmurf(a % N_ACTORS);
        else if (op == OP_WARP) _warp(a, plan);
        else _maybeNewMain(a);
        // Loan flows move ETH and obligations one-for-one; smurf creation buys a ticket and is
        // covered by the solvency floor instead.
        if (op != OP_SMURF && _surplus() != surplusBefore) _flag(4, "backing minus obligations drifted");
    }

    // ------------------------------------------------------------------ actions

    function _seed(uint256 a, uint256 b) internal {
        uint256 idx = a % accts.length;
        uint256 lo = uint256(game.currentLvl()) + 3;
        if (lo > MAX_LEVEL) return;
        uint24 lvl = uint24(lo + (b >> 8) % (MAX_LEVEL - lo + 1));
        _seedAt(idx, lvl, uint32(1 + b % 600));
    }

    function _seedAt(uint256 idx, uint24 lvl, uint32 entries) internal {
        _etch();
        try LoanAccountingSeeder(address(game)).seedLevel(accts[idx].id, lvl, entries) {
            collateral[idx][lvl] += entries;
        } catch {}
        _unetch();
    }

    struct BorrowCtx {
        uint256 idx;
        uint32 id;
        address borrower;
        uint24 lvl;
        uint256 cl;
        uint24 due;
        uint256 amount;
        uint256 principal;
        uint256 ticketWei;
        uint32 lender;
        uint256 minEthOut;
        bool eligible;
        uint256 cashBefore;
        uint256 fundsVault;
        uint256 fundsSdgnrs;
        uint256 next;
        uint256 future;
        uint256 entries;
        uint24 writeKey;
    }

    function _borrow(uint256 a, uint256 b, bool plan) internal {
        BorrowCtx memory c;
        c.lvl = game.currentLvl();
        c.cl = jackpotPhase ? c.lvl : uint256(c.lvl) + 1;
        uint256 maxDue = c.cl + 98 < MAX_LEVEL - 2 ? c.cl + 98 : MAX_LEVEL - 2;
        if (uint256(c.lvl) + 1 > maxDue) return;
        uint256 probe = plan ? 99 : (b >> 64) % 16;
        c.idx = probe == 3 ? a % accts.length : _pickBorrowable(a);
        if (c.idx == type(uint256).max) return;
        uint256 span = maxDue - c.lvl;
        uint256 cap = 1 + (b >> 32) % 16;
        c.due = uint24(c.lvl + 1 + (b >> 8) % (span < cap ? span : cap));
        if (plan || (b & 3) != 0) {
            if (_principalOf(c.idx, c.due, c.cl) < MIN_PRINCIPAL) {
                uint256 hi = c.cl + 100 < MAX_LEVEL ? c.cl + 100 : MAX_LEVEL;
                uint256 room = hi - (uint256(c.due) + 2) + 1;
                _seedAt(c.idx, uint24(uint256(c.due) + 2 + (b >> 96) % (room < 10 ? room : 10)),
                    uint32(4 * (200 + (b >> 128) % 300) + (b >> 160) % 4));
            }
        }
        if (probe == 1) c.due = c.lvl; // due level must be ahead
        if (probe == 2) c.due = uint24(c.cl + 99); // due + 2 must stay within 100 levels
        c.id = accts[c.idx].id;
        c.borrower = actors[accts[c.idx].actor];
        uint256 full = c.due > c.lvl && uint256(c.due) + 2 <= c.cl + 100 ? _principalOf(c.idx, c.due, c.cl) : 0;
        // A quarter of borrows ask for a partial loan, and unplanned ones sometimes for less than the minimum.
        uint256 pick = (b >> 192) % 8;
        if (pick < 2) {
            c.amount = MIN_PRINCIPAL + (b >> 200) % (full > MIN_PRINCIPAL ? full - MIN_PRINCIPAL + 1 : 1);
        } else if (pick == 2 && !plan) {
            c.amount = (b >> 200) % MIN_PRINCIPAL;
        } else {
            c.amount = type(uint256).max;
        }
        c.principal = full < c.amount ? full : c.amount;
        c.ticketWei = _ticketPart(c.principal, c.cl);
        c.lender = _expectedLender(c.principal);
        c.minEthOut = probe == 0 ? c.principal - c.ticketWei + 1 : (probe == 4 ? c.principal - c.ticketWei : 0);
        c.eligible = _borrowable(c.idx) && c.due > c.lvl && uint256(c.due) + 2 <= c.cl + 100
            && c.principal >= MIN_PRINCIPAL && c.lender != 0 && c.principal - c.ticketWei >= c.minEthOut;

        c.cashBefore = _cash(c.borrower);
        c.fundsVault = _funds(VAULT_ID);
        c.fundsSdgnrs = _funds(SDGNRS_ID);
        c.next = game.nextPrizePoolView();
        c.future = game.futurePrizePoolView();
        c.writeKey = _writeKey(uint24(c.cl));
        c.entries = _owedEntries(c.writeKey, c.id);

        vm.prank(c.borrower);
        try game.borrow(c.id, c.due, c.amount, c.minEthOut) {
            if (!c.eligible) {
                _flag(5, "borrow passed a gate the spec closes");
                return;
            }
            _checkBorrow(c);
        } catch (bytes memory reason) {
            if (c.eligible) _flag(3, string.concat("spec-eligible borrow reverted ", vm.toString(reason)));
            else ++ghost_gateRejects;
        }
    }

    function _checkBorrow(BorrowCtx memory c) internal {
        uint256 price = PriceLookupLib.priceForLevel(uint24(c.cl));
        if (_cash(c.borrower) != c.cashBefore + c.principal - c.ticketWei) _flag(3, "borrower cash != principal - ticket part");
        if (_owedEntries(c.writeKey, c.id) != c.entries + c.ticketWei / price * 4) _flag(3, "ticket part entries");
        uint256 toFuture = c.ticketWei / 10;
        if (game.nextPrizePoolView() != c.next + c.ticketWei - toFuture) _flag(3, "ticket part next-pool share != 90%");
        if (game.futurePrizePoolView() != c.future + toFuture) _flag(3, "ticket part future-pool share != 10%");
        DegenerusGameLens.LoanInfo memory info = lens.loanOf(address(game), c.id);
        if (info.principal != c.principal) _flag(3, "recorded principal != spec quote");
        if (info.lenderId != c.lender) _flag(2, "lender != spec lender choice");
        uint256 vaultOut = c.lender == VAULT_ID ? c.principal : 0;
        uint256 sdgnrsOut = c.lender == SDGNRS_ID ? c.principal : 0;
        if (_funds(VAULT_ID) + vaultOut != c.fundsVault || _funds(SDGNRS_ID) + sdgnrsOut != c.fundsSdgnrs) {
            _flag(2, "lender funds moved by other than the principal");
        }
        loans[c.idx] = Loan(c.principal, c.ticketWei, c.lender, c.lvl, c.due, true);
        dueList[c.due].push(c.id);
        if (!dueSeen[c.due]) {
            dueSeen[c.due] = true;
            dueLevels.push(c.due);
        }
        lent[c.lender] += c.principal;
        ++ghost_borrows;
        if (c.ticketWei != 0) ++ghost_ticketBorrows;
        if (!jackpotPhase && GameTimeLib.gameDayIndex() == purchaseStart + TICKET_AFTER_DAYS) ++ghost_day20Borrows;
        if (jackpotPhase) ++ghost_jackpotBorrows;
        if (c.lender == VAULT_ID) ++ghost_vaultLoans;
        if (accts[c.idx].smurf) ++ghost_smurfLoans;
    }

    function _repay(uint256 a, uint256 b, bool plan) internal {
        uint256 idx = _pickOpen(a, plan);
        if (idx == type(uint256).max) return;
        Loan memory l = loans[idx];
        uint32 id = accts[idx].id;
        uint24 lvl = game.currentLvl();
        uint256 c = lvl > l.start ? lvl - l.start : 1;
        uint256 owed = l.principal * (100 + (l.due - l.start) + 4 * c) / 100;
        // Winnings the account may spend on the repayment.
        if (!plan && (b >> 200) & 1 == 1) _credit(id, (b >> 136) % l.principal);
        Bal memory pre = _bal(id);
        uint256 mode = plan ? 3 : b % 6;
        uint256 value = mode == 0 ? 0 : mode == 1 ? owed / 2 : mode == 2 ? owed : mode == 3
            ? owed + (b >> 8) % 1 ether : owed - 1;
        uint256 fresh = value < owed ? value : owed;
        uint256 shortfall = owed - fresh;
        bool ok = _lenderOf(idx) == 0 && (shortfall == 0 || pre.claim > shortfall);
        address payer = actors[accts[idx].actor];
        uint256 lenderFunds = _funds(l.lender);
        vm.deal(payer, payer.balance + value);
        vm.prank(payer);
        try game.clearDebtNow{value: value}(id) {
            if (!ok) {
                _flag(1, "repay succeeded where the spec rejects it");
                return;
            }
            if (_funds(l.lender) != lenderFunds + owed) _flag(1, "repay paid lender != P(100+T+4c)/100");
            Bal memory post = _bal(id);
            if (post.claim != pre.claim - shortfall || post.afk != pre.afk + (value - fresh)) {
                _flag(1, "repay drew/credited the account wrongly");
            }
            if (lens.loanOf(address(game), id).principal != 0) _flag(1, "repaid loan still open");
            receipts[l.lender] += owed;
            _removeDue(l.due, id);
            loans[idx].open = false;
            ++ghost_repays;
            ++ghost_closed;
            if (shortfall != 0) ++ghost_repaysFromClaimable;
        } catch (bytes memory reason) {
            if (ok) _flag(1, string.concat("spec-valid repay reverted ", vm.toString(reason)));
            else ++ghost_gateRejects;
        }
    }

    /// @dev Move the borrower's own balances around the full-term amount: cover it, stop one wei
    ///      short, drain, or overfund. The plan covers a loan that cannot be orphaned first.
    function _steer(uint256 a, uint256 b, bool plan) internal {
        uint256 idx = plan ? _pickSafeOpen(a) : _pickOpen(a, false);
        if (idx == type(uint256).max || _lenderOf(idx) != 0) return;
        Loan memory l = loans[idx];
        uint32 id = accts[idx].id;
        uint256 full = l.principal * (100 + 5 * (l.due - l.start)) / 100;
        Bal memory pre = _bal(id);
        uint256 usable = (pre.claim > 1 ? pre.claim - 1 : 0) + pre.afk;
        uint256 mode = plan ? 0 : b % 4;
        uint256 target = mode == 0 ? full : mode == 1 ? full - 1 : mode == 2 ? 0 : full + (b >> 8) % 1 ether;
        bool viaClaimable = (b >> 128) & 1 == 0;
        if (target > usable) {
            uint256 add = target - usable;
            if (viaClaimable) {
                _credit(id, add);
            } else {
                address payer = actors[accts[idx].actor];
                vm.deal(payer, payer.balance + add);
                vm.prank(payer);
                game.depositAfkingFunding{value: add}(id);
            }
        } else if (target < usable) {
            _withdraw(idx, usable - target);
        }
    }

    function _withdraw(uint256 idx, uint256 amount) internal {
        uint32 id = accts[idx].id;
        address owner = actors[accts[idx].actor];
        Bal memory pre = _bal(id);
        uint256 fromAfk = amount < pre.afk ? amount : pre.afk;
        if (fromAfk != 0) {
            vm.prank(owner);
            game.withdrawAfkingFunding(id, fromAfk);
        }
        uint256 fromClaim = amount - fromAfk;
        if (fromClaim != 0) {
            vm.prank(owner);
            game.claimWinnings(id, fromClaim);
        }
    }

    struct Settle {
        uint32 id;
        uint256 idx;
        bool auto_;
        Bal pre;
        Bal expect;
    }

    function _advance(uint256 a, uint256 b, bool plan) internal {
        uint24 lvl = game.currentLvl();
        uint24 minDue = type(uint24).max;
        for (uint256 i; i < accts.length; ++i) {
            if (loans[i].open && loans[i].due < minDue) minDue = loans[i].due;
        }
        uint24 target;
        if (minDue == type(uint24).max) {
            if (uint256(lvl) + 4 > MAX_LEVEL) return;
            target = uint24(lvl + 1 + a % 3);
        } else {
            target = plan ? minDue : uint24(lvl + 1 + a % (minDue - lvl));
        }
        bool jackpot = (b & 3) == 0;

        // Spec model of the due list in settlement order.
        uint32[] memory list = dueList[target];
        Settle[] memory s = new Settle[](list.length);
        uint256[3] memory expectIn;
        uint256[3] memory fundsBefore = [uint256(0), _funds(VAULT_ID), _funds(SDGNRS_ID)];
        for (uint256 k; k < list.length; ++k) {
            uint256 idx = idxOf[list[k]] - 1;
            Loan memory l = loans[idx];
            if (!l.open || l.due != target) _flag(5, "due list holds a closed or misfiled loan");
            s[k].id = list[k];
            s[k].idx = idx;
            s[k].pre = _bal(list[k]);
            uint256 full = l.principal * (100 + 5 * (l.due - l.start)) / 100;
            uint256 usable = (s[k].pre.claim > 1 ? s[k].pre.claim - 1 : 0) + s[k].pre.afk;
            if (_lenderOf(idx) == 0 && usable >= full) {
                uint256 fromClaim = s[k].pre.claim > 1 ? s[k].pre.claim - 1 : 0;
                if (fromClaim > full) fromClaim = full;
                s[k].auto_ = true;
                s[k].expect = Bal(s[k].pre.claim - fromClaim, s[k].pre.afk - (full - fromClaim));
                expectIn[l.lender] += full;
                receipts[l.lender] += full;
                ++ghost_autoRepays;
            } else {
                if (_lenderOf(idx) != 0) ++ghost_orphanSeizures;
                s[k].expect = s[k].pre;
                accts[idx].seizedTo = l.lender;
                if (!accts[idx].smurf) {
                    liveMain[accts[idx].actor] = 0;
                    ++ghost_mainSeizures;
                }
                ++ghost_seizures;
            }
            loans[idx].open = false;
            ++ghost_closed;
        }

        _etch();
        LoanAccountingSeeder(address(game)).enterDue(target, jackpot);
        _unetch();
        purchaseStart = GameTimeLib.gameDayIndex();
        jackpotPhase = jackpot;
        _runWorker(b);

        if (_pending()) _flag(1, "settlement stage left pending");
        for (uint256 k; k < s.length; ++k) {
            if (lens.loanOf(address(game), s[k].id).principal != 0) _flag(1, "loan neither repaid nor seized at its due level");
            // Final owner: a smurf auto-repaid ahead of its main's seizure still follows the main.
            if (game.acquiredBuyer(s[k].id) != _lenderOf(s[k].idx)) {
                _flag(1, s[k].auto_ ? "covered loan was seized" : "uncovered loan was not seized to its lender");
            }
            Bal memory post = _bal(s[k].id);
            if (post.claim != s[k].expect.claim || post.afk != s[k].expect.afk) {
                _flag(1, s[k].auto_ ? "auto-repay drew balances wrongly" : "seizure moved the account's balances");
            }
            Acct memory ac = accts[s[k].idx];
            if (!s[k].auto_ && !ac.smurf) {
                address seller = actors[ac.actor];
                if (game.walletIdOf_g3120(seller) == s[k].id) _flag(5, "main seizure kept the seller's default ID");
                if (sdgnrsToken.balanceOf(seller) != 0) _flag(5, "main seizure left the seller's sDGNRS");
            }
        }
        for (uint32 l = VAULT_ID; l <= SDGNRS_ID; ++l) {
            if (_funds(l) != fundsBefore[l] + expectIn[l]) _flag(1, "auto-repay paid lender != P(1 + 5%T)");
        }
    }

    function _runWorker(uint256 b) internal {
        if ((b >> 8) & 1 == 1 && game.nextMinerAction() == ACTION_SEIZE_LOANS) {
            uint256 gasCap = 600_000 + (b >> 16) % 2_400_000;
            for (uint256 i; i < 64 && _pending(); ++i) {
                try game.mineRun{gas: gasCap}(0) {} catch { break; }
                ++ghost_chunkedSettles;
            }
        }
        if (_pending()) {
            _etch();
            LoanAccountingSeeder(address(game)).seize();
            _unetch();
        }
    }

    function _sweep(uint256 a, uint256 b) internal {
        uint256 n = accts.length;
        uint256 first = type(uint256).max;
        for (uint256 k; k < n; ++k) {
            uint256 i = (a % n + k) % n;
            if (accts[i].smurf || _lenderOf(i) != 0) {
                first = i;
                break;
            }
        }
        if (first == type(uint256).max) return;
        uint32 owner = _lenderOf(first);
        uint32 creditTo = owner != 0 ? owner : accts[accts[first].mainIdx].id;
        uint32[] memory pick = new uint32[](3);
        uint256 count;
        Bal[] memory pre = new Bal[](3);
        uint256 total;
        for (uint256 k; k < n && count < 3; ++k) {
            uint256 i = (first + k * (1 + b % 3)) % n;
            if (!(accts[i].smurf || _lenderOf(i) != 0) || _lenderOf(i) != owner) continue;
            if (owner == 0 && accts[accts[i].mainIdx].id != creditTo) continue;
            bool dup;
            for (uint256 j; j < count; ++j) if (pick[j] == accts[i].id) dup = true;
            if (dup) continue;
            pick[count] = accts[i].id;
            pre[count] = _bal(accts[i].id);
            total += (pre[count].claim > 1 ? pre[count].claim - 1 : 0) + (owner != 0 ? pre[count].afk : 0);
            ++count;
        }
        uint32[] memory ids = new uint32[](count);
        for (uint256 j; j < count; ++j) ids[j] = pick[j];
        uint256 targetBefore = _bal(creditTo).claim;
        uint256 lenderFunds = owner != 0 ? _funds(owner) : 0;
        bool ok;
        if (owner == VAULT_ID) {
            vm.prank(ContractAddresses.OWNER_GOVERNANCE);
            try vault.playerAction(
                ContractAddresses.GAME,
                abi.encodeWithSignature("sweepAccounts(uint32[])", ids),
                0
            ) {ok = true;} catch {}
        } else {
            vm.prank(owner == SDGNRS_ID ? address(this) : actors[accts[first].actor]);
            try game.sweepAccounts(ids) {ok = true;} catch {}
        }
        if (!ok) {
            _flag(5, "authorized sweep reverted");
            return;
        }
        if (_bal(creditTo).claim != targetBefore + total) _flag(owner != 0 ? 2 : 5, "sweep credited the owner wrongly");
        for (uint256 j; j < count; ++j) {
            Bal memory post = _bal(ids[j]);
            if (post.claim != (pre[j].claim > 1 ? 1 : pre[j].claim) || post.afk != (owner != 0 ? 0 : pre[j].afk)) {
                _flag(5, "sweep left the wrong balances behind");
            }
        }
        if (owner != 0) {
            swept[owner] += total;
            if (_funds(owner) != lenderFunds + total) _flag(2, "sweep moved lender funds by other than the swept amount");
        }
        ++ghost_sweeps;
    }

    function _claim(uint256 a, uint256 b) internal {
        uint256 n = accts.length;
        for (uint256 k; k < n; ++k) {
            uint256 idx = (a % n + k) % n;
            uint32 id = accts[idx].id;
            if (_lenderOf(idx) != 0) continue;
            if (_bal(id).claim <= 1) _credit(id, 1 + (b >> 128) % 1 ether); // winnings to cash out
            Bal memory pre = _bal(id);
            uint256 amount = 1 + b % (pre.claim - 1);
            vm.prank(actors[accts[idx].actor]);
            try game.claimWinnings(id, amount) {
                if (_bal(id).claim != pre.claim - amount) _flag(5, "claim drew the wrong amount");
                ++ghost_claims;
            } catch {
                _flag(5, "owner claim of available winnings reverted");
            }
            return;
        }
    }

    function _createSmurf(uint256 actor) internal {
        uint256 m = liveMain[actor];
        if (m == 0) return;
        m -= 1;
        if (accts[m].smurfs >= MAX_FAMILY) return;
        address owner = actors[actor];
        uint256 price = game.mintPrice();
        vm.deal(owner, owner.balance + price);
        vm.prank(owner);
        try game.createSmurf{value: price}(bytes32(0), MintPaymentKind.DirectEth) returns (uint32 id) {
            if (loans[m].open) _flag(5, "main with an open loan created a smurf");
            ++accts[m].smurfs;
            accts.push(Acct(id, uint8(actor), true, uint16(m), 0, 0));
            idxOf[id] = accts.length;
        } catch {
            if (loans[m].open) ++ghost_gateRejects;
        }
    }

    function _warp(uint256 a, bool plan) internal {
        uint256 daysIn = GameTimeLib.gameDayIndex() - purchaseStart;
        if (daysIn >= MAX_DAYS_IN_PHASE) return;
        uint256 room = MAX_DAYS_IN_PHASE - daysIn;
        uint256 d = plan
            ? (daysIn < TICKET_AFTER_DAYS ? TICKET_AFTER_DAYS - daysIn : 1 + a % 5)
            : 1 + a % (room < 12 ? room : 12);
        if (d > room) d = room;
        vm.warp(block.timestamp + d * 1 days);
        _etch();
        LoanAccountingSeeder(address(game)).sync();
        _unetch();
    }

    function _maybeNewMain(uint256 a) internal {
        uint256 actor = a % N_ACTORS;
        if (liveMain[actor] == 0) _newMain(actor);
    }

    function _newMain(uint256 actor) internal {
        address who = actors[actor];
        vm.prank(ContractAddresses.AFFILIATE);
        uint32 id = game.registerWallet_g9539(who, true);
        vm.prank(ContractAddresses.OWNER_GOVERNANCE);
        game.raiseSmurfBaseAllowance(id, 8);
        vm.prank(address(game));
        sdgnrsToken.transferFromPool_g106128(sDGNRS.Pool.Reward, who, 1e12);
        accts.push(Acct(id, uint8(actor), false, uint16(accts.length), 0, 0));
        idxOf[id] = accts.length;
        liveMain[actor] = accts.length;
    }

    // ------------------------------------------------------------------ spec model

    function _rateBps(uint256 d) internal pure returns (uint256) {
        if (d <= 20) return 1000 - (d - 2) * 500 / 18;
        return 500 - (d - 20) * 300 / 80;
    }

    /// @dev Whole tickets at levels due + 2 .. cl + 100, each valued at its level's price and
    ///      distance rate.
    function _principalOf(uint256 idx, uint24 due, uint256 cl) internal view returns (uint256 p) {
        uint256 hi = cl + 100 < MAX_LEVEL ? cl + 100 : MAX_LEVEL;
        for (uint256 t = uint256(due) + 2; t <= hi; ++t) {
            uint256 tickets = collateral[idx][t] / 4;
            if (tickets == 0) continue;
            p += PriceLookupLib.priceForLevel(uint24(t)) * tickets * _rateBps(t - cl) / 10_000;
        }
    }

    /// @dev Half the principal in whole tickets at the active level once more than 20 days into
    ///      the purchase phase; nothing in the jackpot phase.
    function _ticketPart(uint256 principal, uint256 cl) internal view returns (uint256) {
        if (jackpotPhase || GameTimeLib.gameDayIndex() <= purchaseStart + TICKET_AFTER_DAYS) return 0;
        uint256 price = PriceLookupLib.priceForLevel(uint24(cl));
        return principal / 2 / price * price;
    }

    function _expectedLender(uint256 principal) internal view returns (uint32) {
        if (_bal(SDGNRS_ID).claim >= principal + SDGNRS_RESERVE) return SDGNRS_ID;
        if (_funds(VAULT_ID) > principal + VAULT_FLOOR) return VAULT_ID;
        return 0;
    }

    /// @dev The lender that owns account `idx`: its own default, else its main's.
    function _lenderOf(uint256 idx) internal view returns (uint32) {
        Acct storage ac = accts[idx];
        if (ac.seizedTo != 0) return ac.seizedTo;
        return ac.smurf ? accts[ac.mainIdx].seizedTo : 0;
    }

    function _borrowable(uint256 idx) internal view returns (bool) {
        Acct storage ac = accts[idx];
        if (_lenderOf(idx) != 0 || loans[idx].open) return false;
        return ac.smurf || 1 + uint256(ac.smurfs) <= MAX_FAMILY;
    }

    function _pickBorrowable(uint256 a) internal view returns (uint256) {
        uint256 n = accts.length;
        for (uint256 k; k < n; ++k) {
            uint256 i = (a % n + k) % n;
            if (_borrowable(i)) return i;
        }
        return type(uint256).max;
    }

    /// @dev An open loan; the plan only picks one its owner can still repay.
    function _pickOpen(uint256 a, bool ownedOnly) internal view returns (uint256) {
        uint256 n = accts.length;
        for (uint256 k; k < n; ++k) {
            uint256 i = (a % n + k) % n;
            if (loans[i].open && (!ownedOnly || _lenderOf(i) == 0)) return i;
        }
        return type(uint256).max;
    }

    /// @dev An open loan whose account cannot be acquired before its own due level: a main, or a
    ///      smurf whose main has no open loan.
    function _pickSafeOpen(uint256 a) internal view returns (uint256) {
        uint256 n = accts.length;
        for (uint256 k; k < n; ++k) {
            uint256 i = (a % n + k) % n;
            if (!loans[i].open || _lenderOf(i) != 0) continue;
            if (!accts[i].smurf || !loans[accts[i].mainIdx].open) return i;
        }
        return type(uint256).max;
    }

    function _removeDue(uint24 due, uint32 id) internal {
        uint32[] storage list = dueList[due];
        for (uint256 i; i < list.length; ++i) {
            if (list[i] == id) {
                list[i] = list[list.length - 1];
                list.pop();
                return;
            }
        }
        _flag(5, "repaid loan missing from its due list");
    }

    // ------------------------------------------------------------------ checks (invariants)

    /// @dev Invariant 2: each lender's funds moved by exactly receipts - principals + sweeps.
    function checkLedger() external view {
        for (uint32 l = VAULT_ID; l <= SDGNRS_ID; ++l) {
            assertEq(_funds(l) + lent[l], lenderBase[l] + receipts[l] + swept[l], "lender ledger");
        }
    }

    /// @dev Invariant 5: owners, open loans and due lists match the model.
    function checkOwnership() external view {
        uint24 lvl = game.currentLvl();
        uint256 open;
        for (uint256 i; i < accts.length; ++i) {
            uint32 id = accts[i].id;
            uint32 lender = _lenderOf(i);
            assertEq(game.acquiredBuyer(id), lender, "acquiredBuyer != model owner");
            (, address payee,) = game.resolveAccount_g7029(id, address(0));
            address expected = lender == VAULT_ID ? address(vault)
                : lender == SDGNRS_ID ? address(sdgnrsToken) : actors[accts[i].actor];
            assertEq(payee, expected, "payee != model owner");
            DegenerusGameLens.LoanInfo memory info = lens.loanOf(address(game), id);
            Loan storage l = loans[i];
            if (l.open) {
                ++open;
                assertEq(info.principal, l.principal, "open loan principal");
                assertEq(info.lenderId, l.lender, "open loan lender");
                assertEq(info.startLevel, l.start, "open loan start");
                assertEq(info.dueLevel, l.due, "open loan due");
                assertLt(lvl, l.due, "open loan at or past its due level");
            } else {
                assertEq(info.principal, 0, "closed loan still recorded");
            }
        }
        uint256 listed;
        for (uint256 k; k < dueLevels.length; ++k) {
            uint24 due = dueLevels[k];
            uint32[] memory ids = lens.loansDue(address(game), due);
            uint32[] storage model = dueList[due];
            assertEq(ids.length, model.length, "due list count");
            for (uint256 j; j < ids.length; ++j) assertEq(ids[j], model[j], "due list order");
            if (due > lvl) listed += ids.length;
        }
        assertEq(listed, open, "future due lists != open loans");
    }

    /// @dev Invariant 4: canonical solvency.
    function checkSolvency() external view {
        assertGe(SolvencyObligations.backing(game), SolvencyObligations.obligations(game), "insolvent");
    }

    function violations(uint256 inv) external view returns (uint256, string memory) {
        return (vio[inv], firstVio[inv]);
    }

    // ------------------------------------------------------------------ helpers

    function _flag(uint256 inv, string memory what) internal {
        if (vio[inv]++ == 0) firstVio[inv] = what;
    }

    function _etch() internal {
        vm.etch(address(game), seeder.code);
    }

    function _unetch() internal {
        vm.etch(address(game), gameRuntime);
    }

    function _pending() internal returns (bool on) {
        _etch();
        on = LoanAccountingSeeder(address(game)).pending();
        _unetch();
    }

    /// @dev Backed claimable credit: the Game receives the ETH that backs it.
    function _credit(uint32 id, uint256 amount) internal {
        _etch();
        LoanAccountingSeeder(address(game)).credit(id, uint128(amount));
        _unetch();
        vm.deal(address(game), address(game).balance + amount);
    }

    function _bal(uint32 id) internal view returns (Bal memory b) {
        (uint128 c, uint128 f) = lens.accountBalances(address(game), id);
        b = Bal(c, f);
    }

    function _funds(uint32 id) internal view returns (uint256) {
        Bal memory b = _bal(id);
        return b.claim + b.afk;
    }

    function _cash(address who) internal view returns (uint256) {
        return who.balance + IStETH(ContractAddresses.STETH_TOKEN).balanceOf(who);
    }

    function _writeKey(uint24 lvl) internal view returns (uint24) {
        uint256 slot0 = uint256(vm.load(address(game), bytes32(GameSlots.TICKET_WRITE_SLOT)));
        return uint8(slot0 >> (GameSlots.TICKET_WRITE_SLOT_OFFSET * 8)) == 0 ? lvl : lvl | uint24(1 << 23);
    }

    function _owedEntries(uint24 key, uint32 id) internal view returns (uint256) {
        return uint32(TicketQueueStorage.owedById(address(game), key, id) >> 8);
    }

    function _surplus() internal view returns (int256) {
        return int256(SolvencyObligations.backing(game)) - int256(SolvencyObligations.obligations(game));
    }

    function accountCount() external view returns (uint256) {
        return accts.length;
    }
}
