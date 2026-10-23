// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import "forge-std/Test.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {sDGNRS} from "../../../contracts/sDGNRS.sol";
import {FLIP} from "../../../contracts/FLIP.sol";
import {MockVRFCoordinator} from "../../../contracts/mocks/MockVRFCoordinator.sol";
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";
import {IStETH} from "../../../contracts/interfaces/IStETH.sol";
import {GameTimeLib} from "../../../contracts/libraries/GameTimeLib.sol";
import {BoxOrderLib} from "../../helpers/BoxOrderLib.sol";
import {GameSlots, GameSlotKeys} from "../../helpers/GameSlots.sol";
import {DegenesisReference as Ref} from "../helpers/DegenesisReference.sol";
import {SolvencyObligations} from "../helpers/SolvencyObligations.sol";

/// @title DegenesisSolvencyHandler -- the Degenesis sale driven end to end on the day-1 timeline
/// @notice Actors earn credit through real purchases, buy Degenesis boxes (fresh ETH, overpay,
///         part or wholly from claimable and prepaid AFKing, at any second of the day), redeem
///         FLIP for tickets, claim winnings and fund AFKing; the Vault spends its budget; time moves
///         through the sale and past it; mineFlip runs on varied gas budgets with every VRF request
///         answered; one action may let the game end (deadman) during or after the sale.
///
///         Every mineFlip's logs are replayed in order against the real cohort state:
///         - DegenesisCohortPriced: the cohort is the next unclosed one, its V is the header V and
///           the bought volume, and Q = min(2.5T, R * 2 / 3) with R the Degenesis inventory at that
///           point in the log;
///         - DegenesisOrderResolved: each (day, index) resolves once, in index order, and equals the
///           spec reference for its stored lane, the cohort's frozen V and Q and its bound word;
///         - DegenesisCohortClosed: closes the next cohort once every order resolved, with the
///           paid total announced equal to the resolved sDGNRS sum and at most 1.5Q;
///         - DegenesisCohortSplit: once per cohort, for exactly the header volume;
///         - DegenesisInventoryBurned / DegenesisFundsReleased: the closing burn and terminal
///           release totals.
///         Violations are counted with the first message kept, and the suite asserts zero.
contract DegenesisSolvencyHandler is Test {
    DegenerusGame public game;
    MockVRFCoordinator public vrf;
    sDGNRS public sd;
    FLIP public coin;

    uint256 internal constant UNIT = 0.0001 ether;
    uint256 internal constant MAX_DAY = 17;
    uint256 internal constant N_ACTORS = 6;
    uint32 internal constant SDGNRS_ID = 2;

    bytes32 internal constant SIG_RESOLVED =
        keccak256("DegenesisOrderResolved(uint32,uint8,uint32,uint256,uint256,uint256,uint256,uint32,uint32)");
    bytes32 internal constant SIG_SPLIT = keccak256("DegenesisCohortSplit(uint8,uint256)");
    bytes32 internal constant SIG_PRICED = keccak256("DegenesisCohortPriced(uint8,uint256,uint256,uint24)");
    bytes32 internal constant SIG_CLOSED = keccak256("DegenesisCohortClosed(uint8,uint256)");
    bytes32 internal constant SIG_BURNED = keccak256("DegenesisInventoryBurned(uint256)");
    bytes32 internal constant SIG_RELEASED = keccak256("DegenesisFundsReleased(uint256,uint256)");
    bytes32 internal constant SIG_VAULT_SPENT = keccak256("DegenesisVaultSpent(uint32,uint256)");
    bytes32 internal constant SIG_STAKE = keccak256("CoinflipStakeUpdated(uint32,uint24,uint256,uint256)");

    address[] public actors;

    // ---- ETH flow ghosts ----
    uint256 public ghost_deposited; // ETH actors sent into the Game
    uint256 public ghost_claimed; // ETH + stETH actors took out
    uint256 public ghost_volume; // Σ Degenesis order amounts
    mapping(uint256 => uint256) public ghost_cohortVolume;
    mapping(uint256 => uint256) public ghost_cohortCount;
    uint256 public ghost_splitVolume; // Σ DegenesisCohortSplit volumes
    uint256 public ghost_vaultSpent; // Σ DegenesisVaultSpent costs
    uint256 public ghost_releasedVault;
    uint256 public ghost_releasedSdgnrs;

    // ---- sDGNRS ghosts ----
    uint256 public ghost_dgnrsPaid; // Σ resolved sDGNRS
    uint256 public ghost_inventoryBurned; // closing burn
    uint256 public ghost_gameOverPoolBurn; // inventory burned by the terminal burnAtGameOver
    mapping(uint256 => uint256) public pricedQ;
    mapping(uint256 => uint256) public pricedDay;
    mapping(uint256 => uint256) public cohortPaid;
    mapping(uint256 => uint256) public cohortResolved;
    mapping(uint256 => bool) public cohortSplit;
    uint256 public runningClosed;

    // ---- FLIP ghosts ----
    mapping(uint256 => uint256) public cohortFlipValue;
    uint256 public ghost_flipValue; // Σ FLIP value (coin credit + passes at pass units)
    uint256 public ghost_flipCeiling; // Σ per-order max-rung ceilings
    uint256 public ghost_flipCredited; // Σ coin credit the Coinflip ledger accepted for those orders

    // ---- progress ghosts (non-vacuity) ----
    uint256 public ghost_buys;
    uint256 public ghost_internalBuys; // buys that drew claimable or AFKing
    uint256 public ghost_creditBuys;
    uint256 public ghost_flipRedeems;
    uint256 public ghost_claims;
    uint256 public ghost_vaultSpends;
    uint256 public ghost_mines;
    uint256 public ghost_resolved;
    uint256 public ghost_refChecked;
    uint256 public ghost_refSkipped;
    uint256 public ghost_priced;
    uint256 public ghost_closes;
    uint256 public ghost_endings;
    int256 public ghost_vaultSpendDrift; // backing minus obligations moved by Vault spends
    int256 public ghost_mineDrift; // backing minus obligations moved by live engine calls
    uint256 public ghost_mineDriftCalls;
    uint256 public ghost_terminalDriftCalls;
    uint256 public ghost_revertedMines; // engine calls that reverted (logs discarded)
    bool public ended;
    bool public endedDuringSale;

    // ---- violations ----
    uint256 public violations;
    string public firstViolation;

    constructor(DegenerusGame game_, MockVRFCoordinator vrf_, sDGNRS sd_, FLIP coin_) {
        game = game_;
        vrf = vrf_;
        sd = sd_;
        coin = coin_;
        for (uint256 i; i < N_ACTORS; ++i) {
            address a = address(uint160(0xD6E000 + i));
            actors.push(a);
            vm.deal(a, 100_000 ether);
        }
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    // =====================================================================
    // Readers
    // =====================================================================

    function _now() internal view returns (uint256) {
        return vm.getBlockTimestamp();
    }

    function dayIndex() public view returns (uint256) {
        return (_now() - GameTimeLib.JACKPOT_RESET_TIME) / 1 days + 1;
    }

    function header(uint256 c) public view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(c, GameSlots.DEGENESIS_DAYS))));
    }

    function orderWord(uint256 c, uint256 index) public view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode((c << 32) | (index / 3), GameSlots.DEGENESIS_ORDERS))));
    }

    function lane(uint256 c, uint256 index) public view returns (uint256) {
        return (orderWord(c, index) >> ((index % 3) * 85)) & Ref.LANE_MASK;
    }

    function closed() public view returns (uint256) {
        return uint8(uint256(vm.load(address(game), bytes32(GameSlots.DEGENESIS_CLOSED))) >> (GameSlots.DEGENESIS_CLOSED_OFFSET * 8));
    }

    function active() public view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(GameSlots.DEGENESIS_ACTIVE)));
    }

    function degWord() public view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(GameSlots.DEGENESIS_WORD)));
    }

    function vaultBudget() public view returns (uint256) {
        return uint128(uint256(vm.load(address(game), bytes32(GameSlots.DEGENESIS_VAULT_BUDGET))));
    }

    function degPool() public view returns (uint256) {
        return sd.poolBalance(sDGNRS.Pool.Degenesis);
    }

    /// @dev The ring's word for `day`, authenticated by its parity tag; zero when rotated out.
    function ringWord(uint256 day) public view returns (uint256) {
        uint256 tags = uint256(vm.load(address(game), bytes32(GameSlots.RNG_DAY_TAGS)));
        if (uint24(tags >> ((day & 1) * 24)) != day) return 0;
        return uint256(vm.load(address(game), bytes32(GameSlots.RNG_WORD_BY_DAY + uint256(day & 1))));
    }

    function _balancesOf(uint32 id) internal view returns (uint256) {
        return uint256(vm.load(address(game), GameSlotKeys.balances(id)));
    }

    /// @dev Game backing minus its canonical obligations.
    function surplus() public view returns (int256) {
        return int256(SolvencyObligations.backing(game)) - int256(SolvencyObligations.obligations(game));
    }

    function _flag(string memory why) internal {
        if (violations == 0) firstViolation = why;
        ++violations;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    // =====================================================================
    // Actions
    // =====================================================================

    /// @notice A qualifying ETH purchase: up to 600 tickets and a custom lootbox. Earns 25% credit
    ///         while the credit window is open; the tickets fill the next pool toward its target,
    ///         which opens FLIP redemption and decides the turbo launch.
    function earnCredit(uint256 actorSeed, uint256 boxSeed, uint256 ticketSeed) external {
        if (game.gameOver()) return;
        address a = _actor(actorSeed);
        (,,,, uint256 priceWei) = game.purchaseInfo();
        uint256 box = bound(boxSeed, 0.01 ether, 12 ether) / 0.001 ether * 0.001 ether;
        uint256 qty = ticketSeed % 3 == 0 ? 0 : bound(ticketSeed, 400, 400 * 600);
        uint256 value = box + priceWei * qty / 400;
        vm.prank(a);
        try game.purchase{value: value}(0, qty, BoxOrderLib.boCustom(box), bytes32(0), MintPaymentKind.DirectEth, false) {
            ghost_deposited += value;
            ++ghost_creditBuys;
        } catch {}
    }

    /// @notice Buy a Degenesis box at some second of the day with one of four payment shapes.
    ///         Checks the exact claimablePool move, the 1:1 credit consume, the stored lane and that
    ///         the slot's other lanes are untouched.
    function buyDegenesis(uint256 actorSeed, uint256 amtSeed, uint256 modeSeed, uint256 secsSeed) external {
        if (game.gameOver()) return;
        if (secsSeed % 3 == 0) {
            uint256 dayStart = (dayIndex() - 1) * 1 days + GameTimeLib.JACKPOT_RESET_TIME;
            uint256 target = dayStart + bound(secsSeed >> 8, 0, 1 days - 1);
            if (target > _now()) vm.warp(target);
        }
        address a = _actor(actorSeed);
        uint256 credit = game.degenesisCreditOf(a);
        if (credit < 0.01 ether) return;
        uint256 units = bound(amtSeed, 100, credit / UNIT);
        uint256 amount = units * UNIT;
        uint256 mode = modeSeed % 4;
        uint256 value = mode == 0 ? amount : mode == 1 ? amount + bound(modeSeed >> 8, 1, 1 ether) : mode == 2
            ? amount / 3 : 0;
        uint32 id = game.walletIdOf_g3120(a);
        if (mode >= 2) {
            uint256 have = uint128(_balancesOf(id)) - 1 + (_balancesOf(id) >> 128);
            if (have < amount - value) {
                uint256 dep = amount - value - have;
                vm.prank(a);
                try game.depositAfkingFunding{value: dep}(id) {
                    ghost_deposited += dep;
                } catch {
                    return;
                }
            }
        }
        uint256 c = dayIndex() >= GameTimeLib.DEGENESIS_START_DAY ? dayIndex() - GameTimeLib.DEGENESIS_START_DAY + 1 : 0;
        uint256 hdr = c >= 1 && c <= 7 ? header(c) : 0;
        uint256 index = uint32(hdr >> 48);
        uint256 wordBefore = c >= 1 && c <= 7 ? orderWord(c, index) : 0;
        uint256 poolBefore = game.claimablePoolView();
        int256 surplusBefore = surplus();
        vm.prank(a);
        try game.buyDegenesisBox{value: value}(0, amount) {
            if (surplus() != surplusBefore) _flag("a Degenesis buy moved backing minus obligations");
            if (c < 1 || c > 7) {
                _flag("a Degenesis buy landed outside the sale days");
                return;
            }
            ++ghost_buys;
            if (value < amount) ++ghost_internalBuys;
            ghost_deposited += value;
            ghost_volume += amount;
            ghost_cohortVolume[c] += amount;
            ++ghost_cohortCount[c];
            if (game.claimablePoolView() - poolBefore != value) _flag("buy moved claimablePool by other than msg.value");
            if (game.degenesisCreditOf(a) != credit - amount) _flag("credit not consumed 1:1");
            uint256 secs = (_now() - GameTimeLib.JACKPOT_RESET_TIME) % 1 days;
            if (secs > 6 hours) secs = 6 hours;
            uint256 want = uint256(id) | (units << 32) | (secs << 70);
            uint256 pos = index % 3;
            uint256 wordAfter = orderWord(c, index);
            uint256 expectWord = pos == 0 ? want : wordBefore | (want << (pos * 85));
            if (wordAfter != expectWord) _flag("order slot is not the prior lanes plus the new lane");
            if (header(c) != hdr + units + (uint256(1) << 48)) _flag("header did not add exactly units and one order");
        } catch {}
    }

    /// @notice FLIP-paid tickets earn no Degenesis credit and move no ETH. FLIP redemption opens
    ///         once the next pool passes its target, so a call that finds it short first buys up to
    ///         25 ETH of ordinary tickets (a counted deposit) for the same actor.
    function redeemFlip(uint256 actorSeed, uint256 qtySeed) external {
        if (game.gameOver()) return;
        address a = _actor(actorSeed);
        if (game.nextPrizePoolView() <= 50 ether) {
            (,,,, uint256 priceWei) = game.purchaseInfo();
            uint256 qty = 25 ether / priceWei * 400;
            uint256 value = priceWei * qty / 400;
            vm.prank(a);
            try game.purchase{value: value}(0, qty, 0, bytes32(0), MintPaymentKind.DirectEth, false) {
                ghost_deposited += value;
            } catch {}
        }
        uint256 qtyFlip = bound(qtySeed, 400, 4000);
        vm.prank(address(game));
        coin.mintForGame(a, 10_000_000 ether);
        uint256 credit = game.degenesisCreditOf(a);
        uint256 balBefore = address(game).balance;
        vm.prank(a);
        try game.redeemFlip(0, qtyFlip) {
            ++ghost_flipRedeems;
            if (game.degenesisCreditOf(a) != credit) _flag("FLIP-paid tickets earned credit");
            if (address(game).balance != balBefore) _flag("FLIP-paid tickets moved Game ETH");
        } catch {}
    }

    function fundAfking(uint256 actorSeed, uint256 amtSeed) external {
        address a = _actor(actorSeed);
        uint256 amt = bound(amtSeed, 0.01 ether, 20 ether);
        uint32 id = game.walletIdOf_g3120(a);
        if (id == 0) return;
        vm.prank(a);
        try game.depositAfkingFunding{value: amt}(id) {
            ghost_deposited += amt;
        } catch {}
    }

    function claim(uint256 actorSeed) external {
        address a = _actor(actorSeed);
        IStETH st = IStETH(ContractAddresses.STETH_TOKEN);
        uint256 eth = a.balance;
        uint256 steth = st.balanceOf(a);
        vm.prank(a);
        try game.claimWinnings(0) {
            ++ghost_claims;
            ghost_claimed += (a.balance - eth) + (st.balanceOf(a) - steth);
        } catch {}
    }

    /// @notice The Vault spends budget on tickets (and sometimes a custom lootbox).
    function vaultSpend(uint256 qtySeed, uint256 extraSeed, uint256 boxSeed) external {
        if (game.gameOver()) return;
        uint256 budget = vaultBudget();
        if (budget == 0) return;
        (,,,, uint256 priceWei) = game.purchaseInfo();
        uint256 qty = bound(qtySeed, 400, 2000);
        uint256 box = boxSeed % 2 == 0 ? 0 : bound(boxSeed, 0.01 ether, 0.2 ether) / 0.001 ether * 0.001 ether;
        uint256 cost = priceWei * qty / 400 + box;
        uint256 maxCost = cost + bound(extraSeed, 0, 0.05 ether);
        if (maxCost > budget) return;
        uint256 poolBefore = game.claimablePoolView();
        int256 surplusBefore = surplus();
        vm.recordLogs();
        uint32 recipient = extraSeed % 3 == 0 ? 0 : game.walletIdOf_g3120(_actor(extraSeed));
        vm.prank(ContractAddresses.VAULT);
        try game.spendDegenesis(recipient, false, qty, box == 0 ? 0 : BoxOrderLib.boCustom(box), maxCost) {
            ++ghost_vaultSpends;
            if (surplus() != surplusBefore) ghost_vaultSpendDrift += surplus() - surplusBefore;
            Vm.Log[] memory logs = vm.getRecordedLogs();
            uint256 spent;
            for (uint256 i; i < logs.length; ++i) {
                if (logs[i].emitter == address(game) && logs[i].topics.length > 0 && logs[i].topics[0] == SIG_VAULT_SPENT) {
                    spent += abi.decode(logs[i].data, (uint256));
                }
            }
            ghost_vaultSpent += spent;
            if (budget - vaultBudget() != spent) _flag("budget fell by other than the announced cost");
            if (poolBefore - game.claimablePoolView() != spent) _flag("Vault spend moved claimablePool by other than its cost");
        } catch {
            vm.getRecordedLogs();
        }
    }

    /// @notice Move time forward inside the bounded campaign window.
    function warp(uint256 secsSeed) external {
        if (dayIndex() >= MAX_DAY) return;
        vm.warp(_now() + bound(secsSeed, 60, 36 hours));
    }

    /// @notice Run the engine for a few calls on varied gas budgets, answering every request.
    function mine(uint256 gasSeed, uint256 roundSeed, uint256 wordSeed) external {
        uint256 rounds = bound(roundSeed, 1, 12);
        for (uint256 i; i < rounds; ++i) {
            if (!_mineOnce(gasSeed >> (i * 8), uint256(keccak256(abi.encode(wordSeed, i))))) break;
        }
    }

    /// @notice Let the game end: 32 days with no sealed day trips the deadman, then the engine runs
    ///         the ending to the paid terminal jackpot. One ending per run, on one seed in 32.
    function endGame(uint256 seed) external {
        if (ended || seed % 32 != 0) return;
        ended = true;
        endedDuringSale = closed() < 7;
        vm.warp(_now() + 32 days);
        for (uint256 i; i < 300; ++i) {
            if (game.gameOver() && _jackpotPaid()) break;
            _mineOnce(5, uint256(keccak256(abi.encode(seed, "end", i))));
        }
        if (game.gameOver()) ++ghost_endings;
    }

    function _jackpotPaid() internal view returns (bool) {
        return uint8(uint256(vm.load(address(game), bytes32(GameSlots.GAME_OVER_STATE_PACKED))) >> 48) != 0;
    }

    // =====================================================================
    // Engine call and log replay
    // =====================================================================

    struct Pending {
        uint256 c;
        uint256 index;
        uint32 id;
        uint256 amount;
        uint256 flip;
        uint256 dgnrs;
        uint256 wwxrp;
        uint32 normalPasses;
        uint32 highPasses;
    }

    function _fulfill(uint256 word) internal {
        uint256 req = vrf.lastRequestId();
        if (req == 0) return;
        (,, bool fulfilled) = vrf.pendingRequests(req);
        if (!fulfilled) {
            try vrf.fulfillRandomWords(req, word | 1) {} catch {}
        }
    }

    function _mineOnce(uint256 gasSeed, uint256 word) internal returns (bool ran) {
        _fulfill(word);
        uint256[6] memory budgets = [uint256(700_000), 1_200_000, 2_500_000, 6_000_000, 16_000_000, 30_000_000];
        uint256 g = budgets[gasSeed % 6];
        uint256 wordBefore = degWord();
        uint256 activeBefore = active();
        uint256 poolBefore = degPool();
        bool overBefore = game.gameOver();
        bool livenessBefore = game.livenessTriggered();
        int256 surplusBefore = surplus();
        vm.recordLogs();
        try game.mineFlip{gas: g}(0) {
            ran = true;
            ++ghost_mines;
        } catch {}
        Vm.Log[] memory logs = vm.getRecordedLogs();
        // Recorded logs survive a reverted call (an engine call that ran out of gas); a revert
        // has no state effect, so its logs are discarded unread.
        if (!ran) {
            ++ghost_revertedMines;
            return false;
        }
        // A live engine call moves ETH and obligations together. The terminal transition changes
        // the obligation set itself (SolvencyObligations drops the dead live pools at game over),
        // so calls that end the game or run after liveness are tallied apart.
        int256 drift = surplus() - surplusBefore;
        if (drift != 0) {
            if (!overBefore && !livenessBefore && !game.gameOver() && !game.livenessTriggered()) {
                ghost_mineDrift += drift;
                ++ghost_mineDriftCalls;
            } else {
                ++ghost_terminalDriftCalls;
            }
        }
        if (!overBefore && game.gameOver()) {
            // burnAtGameOver empties the remaining inventory outside any Degenesis event.
            uint256 accounted = _poolOutflow(logs);
            uint256 after_ = degPool();
            if (poolBefore < accounted + after_) _flag("Degenesis inventory rose at game over");
            else ghost_gameOverPoolBurn += poolBefore - accounted - after_;
        }
        _replay(logs, wordBefore, activeBefore, poolBefore);
    }

    function _poolOutflow(Vm.Log[] memory logs) internal view returns (uint256 out) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length == 0) continue;
            bytes32 t = logs[i].topics[0];
            if (t == SIG_RESOLVED) {
                (,,,, uint256 dgnrs,,,) = abi.decode(logs[i].data, (uint8, uint32, uint256, uint256, uint256, uint256, uint32, uint32));
                out += dgnrs;
            } else if (t == SIG_BURNED) {
                out += abi.decode(logs[i].data, (uint256));
            }
        }
    }

    function _replay(Vm.Log[] memory logs, uint256 wordBefore, uint256 activeBefore, uint256 poolBefore) internal {
        uint256 pool = poolBefore;
        Pending[] memory pend = new Pending[](logs.length);
        uint256 np;
        // Coin credit owed by resolved orders, matched in order against the Coinflip ledger's
        // stake events of the chunk's one batch credit.
        uint256[] memory owedIdx = new uint256[](logs.length);
        uint256 owedHead;
        uint256 owedTail;
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory l = logs[i];
            if (l.topics.length == 0) continue;
            if (l.emitter == ContractAddresses.COINFLIP && l.topics[0] == SIG_STAKE && owedHead < owedTail) {
                Pending memory o = pend[owedIdx[owedHead++]];
                (uint256 added,) = abi.decode(l.data, (uint256, uint256));
                if (uint32(uint256(l.topics[1])) != o.id || added != o.flip) _flag("coin credit differs from the resolved FLIP");
                ghost_flipCredited += added;
                continue;
            }
            if (l.emitter != address(game)) continue;
            bytes32 t = l.topics[0];
            if (t == SIG_PRICED) {
                uint256 c = uint256(l.topics[1]);
                (uint256 volume, uint256 qBudget, uint24 boundDay) = abi.decode(l.data, (uint256, uint256, uint24));
                ++ghost_priced;
                if (c != runningClosed + 1) _flag("a cohort priced out of order");
                if (pricedQ[c] != 0) _flag("a cohort priced twice");
                if (volume != uint48(header(c)) * UNIT) _flag("priced V is not the header V");
                if (volume != ghost_cohortVolume[c]) _flag("priced V is not the bought volume");
                if (qBudget != Ref.q(c, pool)) _flag("Q is not min(2.5T, R*2/3)");
                pricedQ[c] = qBudget;
                pricedDay[c] = boundDay;
            } else if (t == SIG_RESOLVED) {
                Pending memory p = pend[np++];
                p.id = uint32(uint256(l.topics[1]));
                uint8 day;
                uint32 index;
                (day, index, p.amount, p.flip, p.dgnrs, p.wwxrp, p.normalPasses, p.highPasses) =
                    abi.decode(l.data, (uint8, uint32, uint256, uint256, uint256, uint256, uint32, uint32));
                p.c = day;
                p.index = index;
                pool -= p.dgnrs;
                _onResolved(p);
                if (p.flip != 0) owedIdx[owedTail++] = np - 1;
            } else if (t == SIG_CLOSED) {
                uint256 c = uint256(l.topics[1]);
                uint256 paid = abi.decode(l.data, (uint256));
                ++ghost_closes;
                if (c != runningClosed + 1) _flag("a cohort closed out of order");
                runningClosed = c;
                if (cohortResolved[c] != uint32(header(c) >> 48)) _flag("a cohort closed with orders unresolved");
                if (paid != cohortPaid[c]) _flag("closed paid total differs from the resolved sum");
                if (paid * 2 > pricedQ[c] * 3) _flag("a cohort paid above 1.5Q");
            } else if (t == SIG_BURNED) {
                uint256 burned = abi.decode(l.data, (uint256));
                if (runningClosed != 7) _flag("inventory burned before the seventh close");
                if (ghost_inventoryBurned != 0) _flag("inventory burned twice");
                if (burned != pool) _flag("the closing burn is not the whole remaining inventory");
                ghost_inventoryBurned += burned;
                pool -= burned;
            } else if (t == SIG_SPLIT) {
                uint256 c = uint256(l.topics[1]);
                uint256 volume = abi.decode(l.data, (uint256));
                if (cohortSplit[c]) _flag("a cohort split twice");
                cohortSplit[c] = true;
                if (volume != uint48(header(c)) * UNIT) _flag("split volume is not the header volume");
                if (volume != ghost_cohortVolume[c]) _flag("split volume is not the bought volume");
                ghost_splitVolume += volume;
            } else if (t == SIG_RELEASED) {
                (uint256 v, uint256 s) = abi.decode(l.data, (uint256, uint256));
                ghost_releasedVault += v;
                ghost_releasedSdgnrs += s;
            }
        }
        if (owedHead != owedTail) _flag("resolved FLIP never reached the Coinflip ledger");
        // The bound word: the one the cohort held entering the call, else the ring's word for its
        // bound day (recorded in this call). Checked after the call, with the lanes still stored.
        for (uint256 k; k < np; ++k) {
            Pending memory p = pend[k];
            uint256 w;
            if (wordBefore != 0 && uint24(activeBefore >> 160) == pricedDay[p.c]) w = wordBefore;
            else w = ringWord(pricedDay[p.c]);
            if (w == 0) {
                ++ghost_refSkipped;
                continue;
            }
            Ref.Outcome memory r = Ref.outcome(w, p.c, p.index, lane(p.c, p.index), uint48(header(p.c)), pricedQ[p.c]);
            ++ghost_refChecked;
            if (r.id != p.id || r.amount != p.amount || r.flip != p.flip || r.dgnrs != p.dgnrs || r.wwxrp != p.wwxrp
                || r.normalPasses != p.normalPasses || r.highPasses != p.highPasses) {
                _flag(string.concat("order differs from the reference: day ", vm.toString(p.c), " index ", vm.toString(p.index)));
            }
        }
    }

    function _onResolved(Pending memory p) internal {
        ++ghost_resolved;
        if (p.c != runningClosed + 1) _flag("an order resolved outside the settling cohort");
        if (p.index != cohortResolved[p.c]) _flag("orders resolved out of index order or twice");
        ++cohortResolved[p.c];
        cohortPaid[p.c] += p.dgnrs;
        ghost_dgnrsPaid += p.dgnrs;
        bool flipSide = p.flip != 0 || p.normalPasses != 0 || p.highPasses != 0;
        if (flipSide && p.dgnrs != 0) _flag("an order paid both FLIP and sDGNRS");
        uint256 v = Ref.flipValue(p.flip, p.normalPasses, p.highPasses);
        uint256 hdr = header(p.c);
        uint256 ceiling = Ref.orderFlipValueCeiling(p.amount / UNIT, p.c, uint48(hdr));
        if (v > ceiling) _flag("an order's FLIP value is above the top-rung ceiling");
        cohortFlipValue[p.c] += v;
        ghost_flipValue += v;
        ghost_flipCeiling += ceiling;
        uint256 l = lane(p.c, p.index);
        if (uint32(l) != p.id || ((l >> 32) & Ref.AMOUNT_MASK) * UNIT != p.amount) _flag("resolved order is not its stored lane");
    }
}
