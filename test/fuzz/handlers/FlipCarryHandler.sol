// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {FLIP} from "../../../contracts/FLIP.sol";
import {Coinflip} from "../../../contracts/Coinflip.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";
import {GameHandler} from "./GameHandler.sol";
import {VRFHandler} from "../helpers/VRFHandler.sol";

/// @title FlipCarryHandler -- stateful driver and ghost model for coinflip bank/carry accounting
/// @notice Drives a fixed set of tracked players (wallet IDs > 3) through the real FLIP and
///         Coinflip entry points and the real mining chain, and keeps an independent model of
///         each player's FLIP position:
///           wallet  -- FLIP balanceOf
///           bank    -- Coinflip claimableStored (settled, unminted winnings)
///           carry   -- Coinflip autoRebuyCarry (rolling auto-rebuy stake)
///           cursor  -- Coinflip lastClaim (last settled day)
///           rebuy / take-profit configuration
///         plus the per-day stake lanes (from CoinflipStakeUpdated) and day results (from
///         CoinflipDayResolved). The model re-implements the settlement walk (win/loss, carry
///         ride with its 0.75% recycling bonus, take-profit banking, the 90-day window, the
///         uint128 carry clamp and claimableStored saturation) and the spend rules of every
///         action from the specification, not from the contract's code paths:
///           gameplay burn: wallet, then bank, then carry -- carry only for IDs > 3 and only
///                          once today's flip is applied; reverts when the three cannot cover it
///           transfer:      wallet, then an auto-claim of the bank; never carry
///           claim:         bank only; claimCoinflipCarry: carry only, never while frozen
///         After every action each tracked player's raw storage must equal the model exactly,
///         and the tracked ledger (wallet + bank + carry + open stake lanes) must equal its
///         starting value plus the documented flows: stake credits, win profit, recycling
///         bonus, losses, forfeits, burns, transfers out, external payouts and clips.
/// @dev The handler is the only fuzz target. Every subcall's logs are drained right after it:
///      vm.getRecordedLogs also returns the logs of reverted calls, so a reverted subcall's logs
///      are discarded and only successful subcalls feed the ghost state.
contract FlipCarryHandler is Test {
    uint256 internal constant MAX128 = type(uint128).max;
    uint256 public constant N = 4;
    uint32 internal constant GNRUS_ID = 3;
    uint256 internal constant WINDOW = 90;
    uint256 internal constant RECYCLE_BPS = 75;
    uint256 internal constant MIN_DEPOSIT = 100;
    uint256 internal constant CRANK_CAP = 64;

    // Coinflip storage (verified against the public views at construction).
    uint256 internal constant PLAYER_STATE_SLOT = 2;
    uint256 internal constant DAYS_SLOT = 4;

    bytes32 internal constant TRANSFER_SIG = keccak256("Transfer(address,address,uint256)");
    bytes32 internal constant STAKE_SIG = keccak256("CoinflipStakeUpdated(uint32,uint24,uint256,uint256)");
    bytes32 internal constant DAY_SIG = keccak256("CoinflipDayResolved(uint24,bool,uint16,uint128)");
    bytes32 internal constant QUEST_SIG = keccak256("QuestCompleted(uint32,uint24,uint8,uint8,uint32,uint256)");
    bytes32 internal constant LEVEL_QUEST_SIG = keccak256("LevelQuestCompleted(uint32,uint24,uint8,uint256)");

    FLIP public immutable coin;
    Coinflip public immutable cf;
    DegenerusGame public immutable game;
    GameHandler public immutable gameH;
    VRFHandler public immutable vrfH;

    address[N] public actors;
    uint32[N] public ids;

    // ------------------------------------------------------------------ model state

    struct Pos {
        uint256 wallet;
        uint256 bank;
        uint256 carry;
        uint24 cursor;
        bool rebuy;
        uint256 tp; // 0 = roll every win
    }

    /// @dev A position plus the ledger flows a simulated step produced; committed only when the
    ///      real call succeeded.
    struct Sim {
        Pos p;
        uint256 winProfit;
        uint256 recycle;
        uint256 loss;
        uint256 forfeit;
        uint256 satClip;
        uint256 mintClip;
        uint256 rides; // wins on which a carry rode and earned a recycling bonus
        uint256 tpBanked; // take-profit chunks banked by the walk
        uint256 wipes; // losses that wiped a carry
    }

    Pos[N] internal pos;
    mapping(uint32 => mapping(uint24 => uint256)) public lane;
    uint24 public maxStakeDay;
    mapping(uint24 => uint8) public dayByte; // 0 unknown, 1 loss, >= 50 win at that reward%
    uint24 public ghostLatest;
    /// @dev The requested-day frontier, sampled only after successful mining-chain steps (the
    ///      only place the Game advances it); the freeze predicate is ghostLatest < ghostRequested.
    uint24 public ghostRequested;
    bool public gapAccepted;

    // ------------------------------------------------------------------ ledger tallies

    uint256 public gL0;
    uint256 public gCredits; // every accepted stake delta to a tracked ID
    uint256 public gPrincipal; // deposit principal moved from wallet/bank into a stake lane
    uint256 public gWinProfit;
    uint256 public gRecycle;
    uint256 public gLoss;
    uint256 public gForfeit;
    uint256 public gBurned; // gameplay burns: wallet + bank + carry legs
    uint256 public gXferOut; // transfers to an untracked holder (the Vault)
    uint256 public gExtMint; // mining-chain FLIP payouts to tracked wallets (Degenerette)
    uint256 public gFunded; // test top-ups (Game mint)
    uint256 public gMintClip; // FLIP mint above the uint128 supply ceiling, not created
    uint256 public gSatClip; // claimableStored saturation and the carry clamp
    uint256 public gInjected; // width-mode injections (value raised)
    uint256 public gEjected; // width-mode injections (value lowered)

    // Global FLIP supply reconciliation (every holder), from the Transfer stream.
    uint256 public immutable initialTotal;
    uint256 public gEvMinted;
    uint256 public gEvBurned;

    // ------------------------------------------------------------------ violation counters

    uint256 public vModel; // a tracked field differs from the model
    uint256 public vLedger; // tracked ledger differs from its documented flows
    uint256 public vSupply; // a subcall's totalSupply delta differs from its Transfer events
    uint256 public vCarryRule; // carry spent where the rules forbid it, or a frozen-carry burn succeeded
    uint256 public vOrder; // a later leg spent while an earlier leg still held value
    uint256 public vConserve; // a burn's legs do not sum to the burned amount
    uint256 public vSpendable; // model spendable vs the documented front-end formula / previews
    uint256 public vUnexpectedRevert; // the model says the call cannot fail, yet it reverted
    uint256 public vDonation; // donor-FLIP oracle
    uint256 public vLane; // CoinflipStakeUpdated newTotal disagrees with the ghost lane
    uint256 public vDays; // day results out of order or disagreeing with storage
    uint256 public vDeposit; // a deposit staked less than principal + rebet recycling bonus
    string public firstFailure;

    // ------------------------------------------------------------------ non-vacuity tallies

    uint256 public constant NP = 33;
    uint256[NP] public hits;
    uint256 internal constant H_DEPOSIT = 0;
    uint256 internal constant H_DEPOSIT_FROM_BANK = 1;
    uint256 internal constant H_REBUY_ON = 2;
    uint256 internal constant H_REBUY_ON_TP = 3;
    uint256 internal constant H_REBUY_OFF = 4;
    uint256 internal constant H_TP_SET = 5;
    uint256 internal constant H_CLAIM = 6;
    uint256 internal constant H_CARRY_CLAIM = 7;
    uint256 internal constant H_BURN = 8; // any successful gameplay burn
    uint256 internal constant H_BURN_BANK = 9; // bank leg > 0
    uint256 internal constant H_BURN_CARRY = 10; // carry leg > 0
    uint256 internal constant H_FROZEN_CARRY_HELD = 11; // frozen, carry held, burn needed it: reverted / bank only
    uint256 internal constant H_REVERSE_FLIP = 12;
    uint256 internal constant H_DEGENERETTE = 13;
    uint256 internal constant H_DECIMATOR = 14;
    uint256 internal constant H_REDEEM_FLIP = 15;
    uint256 internal constant H_TRANSFER = 16;
    uint256 internal constant H_TRANSFER_AUTOCLAIM = 17;
    uint256 internal constant H_DONATION_NOCODE = 18;
    uint256 internal constant H_DONATION_CODE = 19;
    uint256 internal constant H_DONATION_UPLINE = 20; // donor has uplines that stayed unpaid
    uint256 internal constant H_DAY = 21; // a day resolved through the mining chain
    uint256 internal constant H_FROZEN_ACTION = 22; // an action taken while the flip was frozen
    uint256 internal constant H_CARRY_RIDE_BONUS = 23; // a win where carry rode and earned a bonus
    uint256 internal constant H_TP_BANKED = 24; // a take-profit chunk banked by the walk
    uint256 internal constant H_LOSS_WIPED_CARRY = 25;
    uint256 internal constant H_BURN_EXACT = 26; // burn of exactly the spendable total
    uint256 internal constant H_BURN_OVER_REVERT = 27; // spendable + 1 reverted
    uint256 internal constant H_APPLIED_LOCKED = 28; // carry spent while applied but the Game is still locked
    uint256 internal constant H_INJECT = 29;
    uint256 internal constant H_MINT_CLIP = 30;
    uint256 internal constant H_SAT_CLIP = 31;
    uint256 internal constant H_DONATION_VAULT_NOCODE = 32; // Vault Degenesis buy for GNRUS, zero code

    uint256 public actions;
    bool public widthMode;

    constructor(FLIP coin_, Coinflip cf_, DegenerusGame game_, GameHandler gameH_, VRFHandler vrfH_, address[N] memory actors_) {
        coin = coin_;
        cf = cf_;
        game = game_;
        gameH = gameH_;
        vrfH = vrfH_;
        actors = actors_;
        for (uint256 i; i < N; ++i) {
            uint32 id = game_.walletIdOf_g3120(actors_[i]);
            require(id > GNRUS_ID, "actor needs a player wallet ID");
            ids[i] = id;
            (uint256 bank, uint24 cursor, bool rebuy, , , uint256 carry) = _raw(id);
            require(bank == 0 && carry == 0 && !rebuy, "actor must start without a coinflip position");
            require(cf_.coinflipAmountById(id) == 0, "actor must start without stakes");
            pos[i].cursor = cursor;
            pos[i].wallet = coin_.balanceOf(actors_[i]);
            gL0 += pos[i].wallet;
        }
        uint256 daysWord = uint256(vm.load(address(cf_), bytes32(DAYS_SLOT)));
        require(uint24(daysWord >> 176) == cf_.requestedDailyIdx(), "Coinflip day slot layout moved");
        ghostLatest = uint24(daysWord);
        ghostRequested = cf_.requestedDailyIdx();
        initialTotal = coin_.totalSupply();
        vm.recordLogs();
    }

    function enableWidthMode() external {
        widthMode = true;
    }

    // ================================================================== raw reads

    function _stateSlot(uint32 id) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(id), PLAYER_STATE_SLOT));
    }

    /// @dev Raw PlayerCoinflipState: claimableStored, lastClaim, enabled, unlimited, stop, carry.
    function _raw(uint32 id)
        internal
        view
        returns (uint256 bank, uint24 cursor, bool rebuy, bool unlimited, uint256 stop, uint256 carry)
    {
        bytes32 s = _stateSlot(id);
        uint256 a = uint256(vm.load(address(cf), s));
        uint256 b = uint256(vm.load(address(cf), bytes32(uint256(s) + 1)));
        bank = uint128(a);
        cursor = uint24(a >> 128);
        rebuy = uint8(a >> 176) != 0;
        unlimited = uint8(a >> 184) != 0;
        stop = uint128(b);
        carry = b >> 128;
    }

    function rawPosition(uint256 i)
        external
        view
        returns (uint256 bank, uint256 carry, uint24 cursor, bool rebuy)
    {
        (bank, cursor, rebuy, , , carry) = _raw(ids[i]);
    }

    function modelPosition(uint256 i) external view returns (Pos memory) {
        return pos[i];
    }

    function _frozen() internal view returns (bool) {
        return ghostLatest < ghostRequested;
    }

    function frozen() external view returns (bool) {
        return _frozen();
    }

    function _i(uint256 seed) internal pure returns (uint256) {
        return seed % N;
    }

    // ================================================================== model: the settlement walk

    function _load(uint256 i) internal view returns (Sim memory s) {
        s.p = pos[i];
    }

    function _commit(uint256 i, Sim memory s) internal {
        pos[i] = s.p;
        gWinProfit += s.winProfit;
        gRecycle += s.recycle;
        gLoss += s.loss;
        gForfeit += s.forfeit;
        gSatClip += s.satClip;
        gMintClip += s.mintClip;
        if (s.satClip != 0) ++hits[H_SAT_CLIP];
        if (s.mintClip != 0) ++hits[H_MINT_CLIP];
        hits[H_CARRY_RIDE_BONUS] += s.rides;
        hits[H_TP_BANKED] += s.tpBanked;
        hits[H_LOSS_WIPED_CARRY] += s.wipes;
    }

    function _result(uint24 d) internal view returns (uint8 b) {
        b = dayByte[d];
    }

    /// @dev Settle `s` through day `to` (inclusive) and return the walk's mintable. Spec:
    ///      a disabled position folds any leftover carry into mintable; days older than the
    ///      90-day window forfeit (with any carry); each day's stake is its lane plus, while
    ///      rolling, the carry and its 0.75% recycling bonus; a win pays stake * (1 + r%),
    ///      banked in take-profit multiples while rolling, the rest rolls (clamped to uint128);
    ///      a loss wipes the stake and the carry.
    function _walk(Sim memory s, uint32 id, uint24 to) internal view returns (uint256 mintable) {
        uint256 carry;
        if (s.p.rebuy) {
            carry = s.p.carry;
        } else if (s.p.carry != 0) {
            mintable += s.p.carry;
            s.p.carry = 0;
        }
        if (s.p.cursor >= to) return mintable;
        uint256 start = s.p.cursor;
        uint256 minDay = to > WINDOW ? to - WINDOW : 0;
        if (start < minDay) {
            for (uint256 d = start + 1; d <= minDay; ++d) s.forfeit += lane[id][uint24(d)];
            s.forfeit += carry;
            carry = 0;
            start = minDay;
        }
        uint256 tp = s.p.rebuy ? s.p.tp : 0;
        for (uint256 d = start + 1; d <= to; ++d) {
            uint8 b = _result(uint24(d));
            uint256 l = lane[id][uint24(d)];
            uint256 stake = l;
            uint256 bonus;
            if (carry != 0) {
                bonus = (carry * RECYCLE_BPS) / 10_000;
                stake += carry + bonus;
            }
            if (stake == 0) continue;
            if (b >= 50) {
                uint256 profit = (stake * b) / 100;
                uint256 payout = stake + profit;
                s.winProfit += profit;
                s.recycle += bonus;
                if (bonus != 0) ++s.rides;
                if (s.p.rebuy) {
                    uint256 reserved = tp != 0 ? (payout / tp) * tp : 0;
                    mintable += reserved;
                    if (reserved != 0) ++s.tpBanked;
                    carry = payout - reserved;
                    if (carry > MAX128) {
                        s.satClip += carry - MAX128;
                        carry = MAX128;
                    }
                } else {
                    mintable += payout;
                }
            } else {
                // Unresolved days never reach here (to <= ghostLatest); a 0 byte would be a
                // ghost/stream gap and is flagged by the day check.
                s.loss += l + carry;
                if (carry != 0) ++s.wipes;
                carry = 0;
            }
        }
        s.p.cursor = to;
        if (s.p.rebuy) s.p.carry = carry;
    }

    function _sat(Sim memory s, uint256 v) internal pure returns (uint256) {
        if (v > MAX128) {
            s.satClip += v - MAX128;
            return MAX128;
        }
        return v;
    }

    /// @dev FLIP mints stop at the uint128 supply ceiling; the excess is not created.
    function _mintClip(Sim memory s, uint256 amount, uint256 supply) internal pure returns (uint256 minted) {
        uint256 headroom = MAX128 - supply;
        minted = amount > headroom ? headroom : amount;
        s.mintClip += amount - minted;
    }

    // ================================================================== log handling

    function _drain() internal {
        vm.getRecordedLogs();
    }

    function _idx(uint32 id) internal view returns (uint256) {
        for (uint256 i; i < N; ++i) if (ids[i] == id) return i;
        return type(uint256).max;
    }

    function _actorIdx(address a) internal view returns (uint256) {
        for (uint256 i; i < N; ++i) if (actors[i] == a) return i;
        return type(uint256).max;
    }

    /// @dev Feed one successful subcall's logs into the ghost state. `t0` is totalSupply before the
    ///      subcall. With `walletFromEvents` (mining chain only) Transfer mints to tracked wallets
    ///      are external payouts; any other tracked-wallet movement there is unexplained.
    function _ingest(VmSafe.Log[] memory logs, uint256 t0, bool walletFromEvents) internal {
        uint256 dMint;
        uint256 dBurn;
        for (uint256 k; k < logs.length; ++k) {
            VmSafe.Log memory lg = logs[k];
            if (lg.topics.length == 0) continue;
            bytes32 sig = lg.topics[0];
            if (lg.emitter == address(coin) && sig == TRANSFER_SIG && lg.topics.length == 3) {
                address from = address(uint160(uint256(lg.topics[1])));
                address to = address(uint160(uint256(lg.topics[2])));
                uint256 amt = abi.decode(lg.data, (uint256));
                if (from == address(0)) dMint += amt;
                else if (to == address(0)) dBurn += amt;
                if (walletFromEvents) {
                    uint256 fi = _actorIdx(from);
                    uint256 ti = _actorIdx(to);
                    if (from == address(0) && ti != type(uint256).max) {
                        pos[ti].wallet += amt;
                        gExtMint += amt;
                    } else if (fi != type(uint256).max || ti != type(uint256).max) {
                        _fail(vModel, "mining chain moved a tracked wallet other than by a mint", from, to, amt);
                        ++vModel;
                    }
                }
            } else if (lg.emitter == address(cf) && sig == STAKE_SIG) {
                uint32 id = uint32(uint256(lg.topics[1]));
                if (_idx(id) == type(uint256).max) continue;
                uint24 day = uint24(uint256(lg.topics[2]));
                (uint256 amt, uint256 newTotal) = abi.decode(lg.data, (uint256, uint256));
                lane[id][day] += amt;
                gCredits += amt;
                if (day > maxStakeDay) maxStakeDay = day;
                if (lane[id][day] != newTotal) {
                    _fail(vLane, "stake lane total disagrees with the ghost lane", id, day, newTotal);
                    ++vLane;
                }
                if (day <= ghostLatest) {
                    _fail(vLane, "stake credited onto an already-resolved day", id, day, ghostLatest);
                    ++vLane;
                }
            } else if (lg.emitter == address(cf) && sig == DAY_SIG) {
                uint24 day = uint24(uint256(lg.topics[1]));
                (bool win, uint16 rp, ) = abi.decode(lg.data, (bool, uint16, uint128));
                if (day != ghostLatest + 1 && !_fixtureGap(day)) {
                    _fail(vDays, "day resolved out of order", day, ghostLatest, 0);
                    ++vDays;
                }
                dayByte[day] = win ? uint8(rp) : 1;
                ghostLatest = day;
                ++hits[H_DAY];
                (uint16 srp, bool swin) = cf.getCoinflipDayResult(day);
                if (swin != win || (win && srp != rp)) {
                    _fail(vDays, "stored day result disagrees with its event", day, srp, rp);
                    ++vDays;
                }
            }
        }
        gEvMinted += dMint;
        gEvBurned += dBurn;
        if (coin.totalSupply() + dBurn != t0 + dMint) {
            _fail(vSupply, "totalSupply moved without matching Transfer events", t0, coin.totalSupply(), dMint);
            ++vSupply;
        }
    }

    /// @dev The post-Degenesis unit fixture (DeployProtocol at day 9) seeds the request header
    ///      without synthetic results, so the FIRST resolution lands past an unresolved gap. Accept
    ///      that one jump only when no tracked player could have stake or carry in the gap.
    function _fixtureGap(uint24 day) internal returns (bool) {
        if (gapAccepted || day <= ghostLatest) return false;
        for (uint256 i; i < N; ++i) if (pos[i].carry != 0) return false;
        for (uint24 d = ghostLatest + 1; d < day; ++d) {
            (uint16 rp, ) = cf.getCoinflipDayResult(d);
            if (rp != 0) return false;
            for (uint256 i; i < N; ++i) if (lane[ids[i]][d] != 0) return false;
        }
        gapAccepted = true;
        return true;
    }

    /// @dev Stake deltas the logs credit to `id`.
    function _stakeTo(VmSafe.Log[] memory logs, uint32 id) internal view returns (uint256 sum) {
        for (uint256 k; k < logs.length; ++k) {
            VmSafe.Log memory lg = logs[k];
            if (lg.emitter != address(cf) || lg.topics.length < 2 || lg.topics[0] != STAKE_SIG) continue;
            if (uint32(uint256(lg.topics[1])) != id) continue;
            (uint256 amt, ) = abi.decode(lg.data, (uint256, uint256));
            sum += amt;
        }
    }

    function _fail(uint256 counter, string memory what, uint256 a, uint256 b, uint256 c) internal {
        if (counter == 0 && bytes(firstFailure).length == 0) {
            firstFailure = string.concat(
                what, " [action ", vm.toString(actions), "] ", vm.toString(a), " ", vm.toString(b), " ", vm.toString(c)
            );
        }
    }

    function _fail(uint256 counter, string memory what, address a, address b, uint256 c) internal {
        _fail(counter, what, uint256(uint160(a)), uint256(uint160(b)), c);
    }

    // ================================================================== action frame

    modifier action() {
        ++actions;
        vm.recordLogs();
        _;
        _reconcileAll();
    }

    /// @dev Every tracked player's raw storage must equal the model, and the documented
    ///      front-end spendable / preview views must equal the model's settled view.
    function _reconcileAll() internal {
        bool resolvedToday = cf.flipResolvedToday();
        if (resolvedToday == _frozen()) {
            _fail(vDays, "flipResolvedToday disagrees with the ghost frontier", ghostLatest, cf.requestedDailyIdx(), 0);
            ++vDays;
        }
        if (uint24(uint256(vm.load(address(cf), bytes32(DAYS_SLOT)))) != ghostLatest) {
            _fail(vDays, "flipsClaimableDay disagrees with the ghost frontier", ghostLatest, 0, 0);
            ++vDays;
        }
        if (cf.requestedDailyIdx() != ghostRequested) {
            _fail(vDays, "requestedDailyIdx moved outside the mining chain", ghostRequested, cf.requestedDailyIdx(), 0);
            ++vDays;
        }
        uint256 ledger;
        for (uint256 i; i < N; ++i) ledger += _reconcileOne(i, resolvedToday);
        uint256 plus = gL0 + gCredits + gWinProfit + gRecycle + gExtMint + gFunded + gInjected;
        uint256 minus = gPrincipal + gLoss + gForfeit + gBurned + gXferOut + gMintClip + gSatClip + gEjected;
        if (ledger + minus != plus) {
            _fail(vLedger, "tracked ledger != documented flows", ledger, plus, minus);
            ++vLedger;
        }
        if (coin.totalSupply() + gEvBurned != initialTotal + gEvMinted) {
            _fail(vSupply, "global totalSupply != initial + mints - burns", coin.totalSupply(), initialTotal, gEvMinted);
            ++vSupply;
        }
    }

    /// @dev One tracked player: raw storage == model; previews and the documented front-end
    ///      spendable == the model's settled view. Returns the player's contract-side ledger.
    function _reconcileOne(uint256 i, bool resolvedToday) internal returns (uint256 ledger) {
        uint32 id = ids[i];
        Pos memory m = pos[i];
        (uint256 bank, uint24 cursor, bool rebuy, bool unlimited, uint256 stop, uint256 carry) = _raw(id);
        uint256 wallet = coin.balanceOf(actors[i]);
        if (cursor != m.cursor) { _fail(vModel, "cursor", i, m.cursor, cursor); ++vModel; }
        if (bank != m.bank) { _fail(vModel, "bank (claimableStored)", i, m.bank, bank); ++vModel; }
        if (carry != m.carry) { _fail(vModel, "carry (autoRebuyCarry)", i, m.carry, carry); ++vModel; }
        if (wallet != m.wallet) { _fail(vModel, "wallet (balanceOf)", i, m.wallet, wallet); ++vModel; }
        if (rebuy != m.rebuy) { _fail(vModel, "rebuy flag", i, m.rebuy ? 1 : 0, rebuy ? 1 : 0); ++vModel; }
        if (rebuy && m.rebuy) {
            uint256 rawTp = unlimited ? 0 : stop;
            if (rawTp != m.tp || (unlimited && stop != 1)) { _fail(vModel, "take-profit", i, m.tp, rawTp); ++vModel; }
        }
        _checkViews(i, id, resolvedToday);
        // Contract-side ledger: wallet + bank + carry + every lane after the raw cursor.
        ledger = wallet + bank + carry;
        for (uint256 d = uint256(cursor) + 1; d <= maxStakeDay; ++d) ledger += lane[id][uint24(d)];
    }

    function _checkViews(uint256 i, uint32 id, bool resolvedToday) internal {
        Sim memory s = _load(i);
        uint256 mintable = _walk(s, id, ghostLatest);
        uint256 settledBank = s.p.bank + mintable;
        uint256 claimView = cf.previewClaimCoinflipsById(id);
        uint256 backingView = cf.previewFlipBackingById(id);
        if (claimView != settledBank) { _fail(vSpendable, "previewClaimCoinflips", i, settledBank, claimView); ++vSpendable; }
        if (backingView != settledBank + s.p.carry) {
            _fail(vSpendable, "previewFlipBacking", i, settledBank + s.p.carry, backingView);
            ++vSpendable;
        }
        // Documented front-end gameplay balance: balanceOfWithClaimable plus, while
        // flipResolvedToday(), previewFlipBacking - previewClaimCoinflips.
        uint256 frontEnd = coin.balanceOfWithClaimable(actors[i])
            + (resolvedToday && backingView >= claimView ? backingView - claimView : 0);
        uint256 spend = s.p.wallet + settledBank + (_frozen() ? 0 : s.p.carry);
        if (frontEnd != spend) { _fail(vSpendable, "front-end spendable", i, spend, frontEnd); ++vSpendable; }
    }

    /// @notice No-op action: reconcile only (self-tests).
    function checkpoint() external action {}

    // ================================================================== coinflip actions

    /// @notice playCoinflip(0, amount): settle, then stake from the bank first and the wallet for
    ///         the rest. amount 0 settles only.
    function deposit(uint256 actorSeed, uint256 amtSeed) external action {
        uint256 i = _i(actorSeed);
        uint32 id = ids[i];
        Sim memory s = _load(i);
        uint256 mintable = _walk(s, id, ghostLatest);
        uint256 stored = s.p.bank;
        if (mintable != 0) stored = _sat(s, stored + mintable);
        uint256 budget = s.p.wallet + stored;
        uint256 amount = amtSeed % 5 == 0 || budget < MIN_DEPOSIT ? 0 : bound(amtSeed, MIN_DEPOSIT, budget);
        if (amount > 100_000_000) amount = 100_000_000;
        // A manual deposit reverts past the day's whole-FLIP lane cap (with its bonuses).
        bool nearCap = lane[id][cf.requestedDailyIdx() + 1] + 2 * amount + 1_000_000 > type(uint32).max;
        uint256 fromBank = amount < stored ? amount : stored;
        s.p.bank = stored - fromBank;
        uint256 fromWallet = amount - fromBank;
        bool feasible = fromWallet <= s.p.wallet;
        if (feasible) s.p.wallet -= fromWallet;
        if (_frozen()) ++hits[H_FROZEN_ACTION];

        uint256 t0 = coin.totalSupply();
        _drain();
        vm.prank(actors[i]);
        try cf.playCoinflip(0, amount) {
            VmSafe.Log[] memory logs = vm.getRecordedLogs();
            _ingest(logs, t0, false);
            if (!feasible) { _fail(vConserve, "deposit beyond wallet + bank succeeded", i, amount, budget); ++vConserve; }
            _commit(i, s);
            gPrincipal += amount;
            if (amount != 0) {
                ++hits[H_DEPOSIT];
                if (fromBank != 0) ++hits[H_DEPOSIT_FROM_BANK];
                uint256 staked = _stakeTo(logs, id);
                uint256 floor_ = amount + (fromBank * RECYCLE_BPS) / 10_000;
                if (staked < floor_) { _fail(vDeposit, "deposit staked less than principal + rebet bonus", i, floor_, staked); ++vDeposit; }
            }
        } catch {
            _drain();
            if (feasible && !nearCap && !game.gameOver()) {
                _fail(vUnexpectedRevert, "feasible deposit reverted", i, amount, budget);
                ++vUnexpectedRevert;
            }
        }
    }

    /// @notice setCoinflipAutoRebuy(0, enabled, takeProfit).
    function setRebuy(uint256 actorSeed, bool enable, uint256 tpSeed) external action {
        uint256 i = _i(actorSeed);
        uint32 id = ids[i];
        uint256 tp = tpSeed % 3 == 0 ? 0 : bound(tpSeed, 1_000, 200_000);
        Sim memory s = _load(i);
        bool expectOk = !(_frozen() && s.p.rebuy) && !(enable && s.p.rebuy);
        uint256 mintable = _walk(s, id, ghostLatest);
        if (!enable) {
            mintable += s.p.carry;
            s.p.carry = 0;
        }
        s.p.rebuy = enable;
        s.p.tp = enable ? tp : 0;
        uint256 t0 = coin.totalSupply();
        s.p.wallet += _mintClip(s, mintable, t0);
        if (_frozen()) ++hits[H_FROZEN_ACTION];

        _drain();
        vm.prank(actors[i]);
        try cf.setCoinflipAutoRebuy(0, enable, tp) {
            _ingest(vm.getRecordedLogs(), t0, false);
            if (!expectOk) { _fail(vCarryRule, "auto-rebuy change accepted while gated", i, enable ? 1 : 0, 0); ++vCarryRule; }
            _commit(i, s);
            if (enable) ++hits[tp == 0 ? H_REBUY_ON : H_REBUY_ON_TP];
            else ++hits[H_REBUY_OFF];
        } catch {
            _drain();
            if (expectOk) { _fail(vUnexpectedRevert, "ungated auto-rebuy change reverted", i, enable ? 1 : 0, tp); ++vUnexpectedRevert; }
        }
    }

    /// @notice setCoinflipAutoRebuyTakeProfit(0, takeProfit).
    function setTakeProfit(uint256 actorSeed, uint256 tpSeed) external action {
        uint256 i = _i(actorSeed);
        uint32 id = ids[i];
        uint256 tp = tpSeed % 4 == 0 ? 0 : bound(tpSeed, 1_000, 200_000);
        Sim memory s = _load(i);
        bool expectOk = s.p.rebuy && !_frozen();
        uint256 mintable = _walk(s, id, ghostLatest);
        s.p.tp = tp;
        uint256 t0 = coin.totalSupply();
        s.p.wallet += _mintClip(s, mintable, t0);

        _drain();
        vm.prank(actors[i]);
        try cf.setCoinflipAutoRebuyTakeProfit(0, tp) {
            _ingest(vm.getRecordedLogs(), t0, false);
            if (!expectOk) { _fail(vCarryRule, "take-profit change accepted while gated", i, tp, 0); ++vCarryRule; }
            _commit(i, s);
            ++hits[H_TP_SET];
        } catch {
            _drain();
            if (expectOk) { _fail(vUnexpectedRevert, "ungated take-profit change reverted", i, tp, 0); ++vUnexpectedRevert; }
        }
    }

    /// @notice claimCoinflips(0, amount): bank only, minted to the wallet. Never reverts.
    function claim(uint256 actorSeed, uint256 amtSeed) external action {
        uint256 i = _i(actorSeed);
        uint32 id = ids[i];
        Sim memory s = _load(i);
        uint256 mintable = _walk(s, id, ghostLatest);
        uint256 carryWalked = s.p.carry;
        uint256 stored = s.p.bank + mintable;
        uint256 amount = amtSeed % 3 == 0 ? type(uint256).max : bound(amtSeed, 0, stored + 1_000);
        uint256 claimed = amount < stored ? amount : stored;
        s.p.bank = _sat(s, stored - claimed);
        uint256 t0 = coin.totalSupply();
        s.p.wallet += _mintClip(s, claimed, t0);
        if (_frozen()) ++hits[H_FROZEN_ACTION];

        _drain();
        vm.prank(actors[i]);
        try cf.claimCoinflips(0, amount) returns (uint256 got) {
            _ingest(vm.getRecordedLogs(), t0, false);
            _commit(i, s);
            if (got != claimed) { _fail(vModel, "claimCoinflips return", i, claimed, got); ++vModel; }
            (, , , , , uint256 rawCarry) = _raw(id);
            if (rawCarry != carryWalked) { _fail(vCarryRule, "claimCoinflips moved the carry", i, carryWalked, rawCarry); ++vCarryRule; }
            if (claimed != 0) ++hits[H_CLAIM];
        } catch {
            _drain();
            _fail(vUnexpectedRevert, "claimCoinflips reverted", i, amount, stored);
            ++vUnexpectedRevert;
        }
    }

    /// @notice claimCoinflipCarry(0, amount): carry only; gated on rebuy and an applied flip.
    function claimCarry(uint256 actorSeed, uint256 amtSeed) external action {
        uint256 i = _i(actorSeed);
        uint32 id = ids[i];
        Sim memory s = _load(i);
        bool expectOk = s.p.rebuy && !_frozen();
        uint256 mintable = _walk(s, id, ghostLatest);
        if (mintable != 0) s.p.bank = _sat(s, s.p.bank + mintable);
        uint256 amount = amtSeed % 3 == 0 ? type(uint256).max : bound(amtSeed, 0, s.p.carry + 1_000);
        uint256 claimed = amount < s.p.carry ? amount : s.p.carry;
        s.p.carry -= claimed;
        uint256 t0 = coin.totalSupply();
        s.p.wallet += _mintClip(s, claimed, t0);
        if (_frozen()) ++hits[H_FROZEN_ACTION];

        _drain();
        vm.prank(actors[i]);
        try cf.claimCoinflipCarry(0, amount) returns (uint256 got) {
            _ingest(vm.getRecordedLogs(), t0, false);
            if (!expectOk) { _fail(vCarryRule, "carry claim accepted while gated", i, s.p.rebuy ? 1 : 0, 0); ++vCarryRule; }
            _commit(i, s);
            if (got != claimed) { _fail(vModel, "claimCoinflipCarry return", i, claimed, got); ++vModel; }
            if (claimed != 0) ++hits[H_CARRY_CLAIM];
        } catch {
            _drain();
            if (expectOk) { _fail(vUnexpectedRevert, "ungated carry claim reverted", i, amount, 0); ++vUnexpectedRevert; }
        }
    }

    // ================================================================== gameplay burns

    struct BurnPlan {
        bool feasible;
        bool frozen;
        uint256 fromWallet;
        uint256 fromBank;
        uint256 fromCarry;
        uint256 storedWalked; // bank + walk mintable, before the spend
        uint256 carryWalked;
        bool walked;
    }

    /// @dev The specification's gameplay-burn waterfall for `A` FLIP from tracked player `i`.
    function _planBurn(Sim memory s, uint256 i, uint256 A) internal view returns (BurnPlan memory b) {
        b.frozen = _frozen();
        uint256 W = s.p.wallet;
        if (W >= A) {
            b.feasible = true;
            b.fromWallet = A;
            s.p.wallet = W - A;
            b.storedWalked = s.p.bank;
            b.carryWalked = s.p.carry;
            return b;
        }
        b.walked = true;
        uint256 need = A - W;
        uint256 mintable = _walk(s, ids[i], ghostLatest);
        uint256 stored = s.p.bank + mintable;
        b.storedWalked = stored;
        b.carryWalked = s.p.carry;
        b.fromBank = need < stored ? need : stored;
        s.p.bank = _sat(s, stored - b.fromBank);
        if (b.fromBank < need && ids[i] > GNRUS_ID && !b.frozen) {
            uint256 rest = need - b.fromBank;
            b.fromCarry = rest < s.p.carry ? rest : s.p.carry;
            s.p.carry -= b.fromCarry;
        }
        b.fromWallet = W;
        b.feasible = b.fromBank + b.fromCarry == need;
        s.p.wallet = 0;
    }

    /// @dev Post-call checks for a successful gameplay burn of `A` against its plan, from the raw
    ///      storage (independent of the commit): legs sum to A, order wallet -> bank -> carry, and
    ///      the carry rule.
    function _checkBurn(uint256 i, uint256 A, BurnPlan memory b, uint256 walletBefore) internal {
        (uint256 bank, , , , , uint256 carry) = _raw(ids[i]);
        uint256 wallet = coin.balanceOf(actors[i]);
        uint256 wLeg = walletBefore > wallet ? walletBefore - wallet : 0;
        uint256 bLeg = b.storedWalked > bank ? b.storedWalked - bank : 0;
        uint256 cLeg = b.carryWalked > carry ? b.carryWalked - carry : 0;
        if (b.storedWalked > MAX128) bLeg = b.fromBank; // saturated bank: the raw delta is clipped
        if (wLeg + bLeg + cLeg != A) { _fail(vConserve, "burn legs != burned amount", wLeg + bLeg, cLeg, A); ++vConserve; }
        if ((bLeg != 0 || cLeg != 0) && wallet != 0) { _fail(vOrder, "bank/carry spent with wallet left", i, wallet, bLeg + cLeg); ++vOrder; }
        if (cLeg != 0 && bank != 0) { _fail(vOrder, "carry spent with bank left", i, bank, cLeg); ++vOrder; }
        if (cLeg != 0 && (b.frozen || ids[i] <= GNRUS_ID)) { _fail(vCarryRule, "carry spent while frozen / protocol ID", i, cLeg, 0); ++vCarryRule; }
        if (!b.feasible) { _fail(vCarryRule, "burn beyond wallet + bank + spendable carry succeeded", i, A, 0); ++vCarryRule; }
        ++hits[H_BURN];
        if (bLeg != 0) ++hits[H_BURN_BANK];
        if (cLeg != 0) {
            ++hits[H_BURN_CARRY];
            if (game.rngLocked()) ++hits[H_APPLIED_LOCKED];
        }
    }

    /// @dev Frozen, and only the held carry could have completed the burn: it had to revert.
    function _tallyFrozenHold(BurnPlan memory b, uint256 A) internal {
        uint256 covered = b.fromWallet + b.fromBank;
        if (b.frozen && b.walked && covered < A && covered + b.carryWalked >= A) ++hits[H_FROZEN_CARRY_HELD];
    }

    /// @dev Shared body: run `call` (a burn of A by tracked player i), then reconcile.
    ///      `exact` = the call's only failure mode is an infeasible burn (direct FLIP burn).
    function _burn(uint256 i, uint256 A, bytes memory callData, address target, bool asGame, bool exact, uint256 hit)
        internal
        returns (bool ok)
    {
        Sim memory s = _load(i);
        BurnPlan memory b = _planBurn(s, i, A);
        if (b.frozen) ++hits[H_FROZEN_ACTION];
        uint256 walletBefore = coin.balanceOf(actors[i]);
        uint256 t0 = coin.totalSupply();
        _drain();
        vm.prank(asGame ? ContractAddresses.GAME : actors[i]);
        (ok, ) = target.call(callData);
        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        if (ok) {
            _ingest(logs, t0, false);
            _commit(i, s);
            gBurned += A;
            _checkBurn(i, A, b, walletBefore);
            if (hit != type(uint256).max) ++hits[hit];
        } else {
            if (exact && b.feasible) { _fail(vUnexpectedRevert, "feasible gameplay burn reverted", i, A, b.fromBank + b.fromCarry); ++vUnexpectedRevert; }
            _tallyFrozenHold(b, A);
        }
    }

    /// @notice Spendable under the specification: wallet + settled bank + carry when applied.
    function spendable(uint256 i) public view returns (uint256) {
        Sim memory s = _load(i);
        uint256 mintable = _walk(s, ids[i], ghostLatest);
        return s.p.wallet + s.p.bank + mintable + (_frozen() ? 0 : s.p.carry);
    }

    /// @notice FLIP's gameplay burn (burnCoin_g27673) as the Game would call it.
    function gameBurn(uint256 actorSeed, uint256 amtSeed) external action {
        uint256 i = _i(actorSeed);
        uint256 cap = spendable(i);
        uint256 A = bound(amtSeed, 1, cap + cap / 4 + 1);
        _burn(i, A, abi.encodeCall(FLIP.burnCoin_g27673, (actors[i], A)), address(coin), true, true, type(uint256).max);
    }

    /// @notice Burn exactly the spendable total (must succeed and empty every spendable leg), or
    ///         one more (must revert).
    function burnExact(uint256 actorSeed, bool over) external action {
        uint256 i = _i(actorSeed);
        uint256 S = spendable(i);
        if (S == 0) return;
        uint256 A = over ? S + 1 : S;
        bool ok = _burn(i, A, abi.encodeCall(FLIP.burnCoin_g27673, (actors[i], A)), address(coin), true, true, type(uint256).max);
        if (over) {
            if (ok) { _fail(vConserve, "spendable + 1 burn succeeded", i, S, 0); ++vConserve; }
            else ++hits[H_BURN_OVER_REVERT];
        } else if (ok) {
            ++hits[H_BURN_EXACT];
            // Settled views (a resolved loss the burn did not need to walk has already wiped
            // the raw carry): wallet + settled bank + settled carry when applied.
            uint32 id = ids[i];
            uint256 left = coin.balanceOf(actors[i])
                + (_frozen() ? cf.previewClaimCoinflipsById(id) : cf.previewFlipBackingById(id));
            if (left != 0) { _fail(vConserve, "exact-spendable burn left spendable value", i, left, 0); ++vConserve; }
        }
    }

    /// @notice Game.reverseFlip: a gameplay FLIP burn at the live nudge price.
    function reverseFlip(uint256 actorSeed) external action {
        uint256 i = _i(actorSeed);
        (, uint256 cost) = game.rngNudgeQuote();
        if (cost == 0) return;
        _burn(i, cost, abi.encodeWithSignature("reverseFlip(uint256)", cost), address(game), false, false, H_REVERSE_FLIP);
    }

    /// @notice Game.betDegenerette in FLIP: the bet's total burns through the gameplay waterfall.
    function degeneretteFlip(uint256 actorSeed, uint256 perSpinSeed, uint256 spinsSeed, uint256 symbolSeed) external action {
        uint256 i = _i(actorSeed);
        uint128 perSpin = uint128(bound(perSpinSeed, 100, 5_000));
        uint8 spins = uint8(bound(spinsSeed, 1, 15));
        uint8 symbol = uint8(symbolSeed % 24);
        uint256 A = uint256(perSpin) * spins;
        _burn(
            i, A, abi.encodeWithSignature("betDegenerette(uint32,uint8,uint128,uint8,uint8)", uint32(0), uint8(1), perSpin, spins, symbol),
            address(game), false, false, H_DEGENERETTE
        );
    }

    /// @notice FLIP.decimatorBurn during a Decimator window.
    function decimatorBurn(uint256 actorSeed, uint256 amtSeed) external action {
        uint256 i = _i(actorSeed);
        if (!game.decimatorActive()) return;
        uint256 A = bound(amtSeed, 2_000, 20_000);
        _burn(i, A, abi.encodeCall(FLIP.decimatorBurn, (0, A, 0)), address(coin), false, false, H_DECIMATOR);
    }

    /// @notice Game.redeemFlip: FLIP-paid tickets (jackpot window only).
    function redeemFlip(uint256 actorSeed, uint256 qtySeed) external action {
        uint256 i = _i(actorSeed);
        uint256 q = bound(qtySeed, 1, 8) * 400;
        uint256 A = (q * 250 + 99) / 100;
        _burn(i, A, abi.encodeWithSignature("redeemFlip(uint32,uint256)", uint32(0), q), address(game), false, false, H_REDEEM_FLIP);
    }

    // ================================================================== transfers and funding

    /// @notice FLIP transfer: the wallet first, then an auto-claim of the bank; never the carry.
    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amtSeed, bool toVault) external action {
        uint256 i = _i(fromSeed);
        uint256 j = _i(toSeed);
        address to = toVault ? ContractAddresses.VAULT : actors[j];
        Sim memory s = _load(i);
        uint256 W = s.p.wallet;
        Sim memory probe = _load(i);
        uint256 budget = W + probe.p.bank + _walk(probe, ids[i], ghostLatest);
        uint256 amt = bound(amtSeed, 1, budget + budget / 8 + 1);
        uint256 t0 = coin.totalSupply();
        bool autoClaim;
        if (W < amt) {
            autoClaim = true;
            uint256 mintable = _walk(s, ids[i], ghostLatest);
            uint256 stored = s.p.bank + mintable;
            uint256 need = amt - W;
            uint256 claimed = need < stored ? need : stored;
            s.p.bank = _sat(s, stored - claimed);
            s.p.wallet += _mintClip(s, claimed, t0);
        }
        uint256 carryWalked = s.p.carry;
        bool feasible = s.p.wallet >= amt;
        if (feasible) s.p.wallet -= amt;
        if (_frozen()) ++hits[H_FROZEN_ACTION];

        _drain();
        vm.prank(actors[i]);
        try coin.transfer(to, amt) {
            _ingest(vm.getRecordedLogs(), t0, false);
            if (!feasible) { _fail(vCarryRule, "transfer beyond wallet + bank succeeded (carry reached?)", i, amt, budget); ++vCarryRule; }
            _commit(i, s);
            if (toVault) gXferOut += amt;
            else pos[j].wallet += amt;
            (, , , , , uint256 rawCarry) = _raw(ids[i]);
            if (rawCarry != carryWalked) { _fail(vCarryRule, "transfer moved the carry", i, carryWalked, rawCarry); ++vCarryRule; }
            ++hits[H_TRANSFER];
            if (autoClaim) ++hits[H_TRANSFER_AUTOCLAIM];
        } catch {
            _drain();
            if (feasible) { _fail(vUnexpectedRevert, "feasible transfer reverted", i, amt, budget); ++vUnexpectedRevert; }
        }
    }

    /// @notice Top up a tracked wallet through the Game's mint door (keeps the campaign liquid).
    function fund(uint256 actorSeed, uint256 amtSeed) external action {
        uint256 i = _i(actorSeed);
        uint256 amt = bound(amtSeed, 1_000, 50_000);
        uint256 t0 = coin.totalSupply();
        Sim memory s = _load(i);
        uint256 minted = _mintClip(s, amt, t0);
        _drain();
        vm.prank(ContractAddresses.GAME);
        coin.mintForGame_g152734(actors[i], amt);
        _ingest(vm.getRecordedLogs(), t0, false);
        s.p.wallet += minted;
        _commit(i, s); // books any part above the supply ceiling as a mint clip
        gFunded += amt;
    }

    // ================================================================== purchases

    /// @notice An ordinary ticket purchase by a tracked player (earns its own FLIP stake credits).
    function buyTickets(uint256 actorSeed, uint256 qtySeed) external action {
        uint256 i = _i(actorSeed);
        (, , , , uint256 price) = game.purchaseInfo_g1027();
        uint256 q = bound(qtySeed, 1, 12) * 400;
        uint256 cost = (price * q) / 400;
        vm.deal(actors[i], actors[i].balance + cost);
        uint256 t0 = coin.totalSupply();
        _drain();
        vm.prank(actors[i]);
        try game.purchaseOrderFor{value: cost}(0, q, 0, bytes32(0), MintPaymentKind.DirectEth, false) {
            _ingest(vm.getRecordedLogs(), t0, false);
        } catch {
            _drain();
        }
    }

    /// @notice A GameHandler-actor purchase (keeps the game progressing).
    function purchase(uint256 actorSeed, uint256 qty, uint256 lootboxAmt) external action {
        uint256 adv = gameH.ghost_successfulPurchases();
        uint256 t0 = coin.totalSupply();
        _drain();
        gameH.purchase(actorSeed, qty, lootboxAmt);
        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        if (gameH.ghost_successfulPurchases() != adv) _ingest(logs, t0, true);
    }

    struct DonationExpect {
        uint32 donorId;
        uint256 bonus;
        uint256 scaledA; // accepted commission values: base, and the two affiliate-bonus-day boosts
        uint256 scaledB;
        uint256 scaledC;
    }

    uint256 internal constant DV_DONOR_AMOUNT = 1;
    uint256 internal constant DV_GNRUS_EXTRA = 2;
    uint256 internal constant DV_OTHER_PAID = 4;
    uint256 internal constant DV_DONOR_WRITES = 8;

    /// @notice The donor-FLIP oracle over one successful donation's logs (pure, so self-tests can
    ///         feed it doctored logs). Spec: the donor's stake rises by the purchase bonus plus the
    ///         whole commission in ONE stake write, plus only its own quest rewards; GNRUS's stake
    ///         rises by its own quest rewards alone (its bonus moved to the donor); nobody else --
    ///         uplines, VAULT, sDGNRS -- is credited.
    function donationViolations(VmSafe.Log[] memory logs, DonationExpect memory e) public pure returns (uint256 bits) {
        uint256 donorSum;
        uint256 donorWrites;
        uint256 gnrusSum;
        uint256 donorQuest;
        uint256 donorLevelQuests;
        uint256 gnrusQuest;
        for (uint256 k; k < logs.length; ++k) {
            VmSafe.Log memory lg = logs[k];
            if (lg.topics.length < 2) continue;
            bytes32 sig = lg.topics[0];
            uint32 id = uint32(uint256(lg.topics[1]));
            if (lg.emitter == ContractAddresses.COINFLIP && sig == STAKE_SIG) {
                (uint256 amt, ) = abi.decode(lg.data, (uint256, uint256));
                if (id == e.donorId) {
                    donorSum += amt;
                    ++donorWrites;
                } else if (id == GNRUS_ID) {
                    gnrusSum += amt;
                } else if (amt != 0) {
                    bits |= DV_OTHER_PAID;
                }
            } else if (lg.emitter == ContractAddresses.QUESTS && sig == QUEST_SIG) {
                (, , uint256 reward) = abi.decode(lg.data, (uint8, uint32, uint256));
                if (id == e.donorId) donorQuest += reward;
                else if (id == GNRUS_ID) gnrusQuest += reward;
            } else if (lg.emitter == ContractAddresses.QUESTS && sig == LEVEL_QUEST_SIG) {
                (, uint256 reward) = abi.decode(lg.data, (uint8, uint256));
                if (id == e.donorId) {
                    donorQuest += reward;
                    ++donorLevelQuests;
                } else if (id == GNRUS_ID) {
                    gnrusQuest += reward;
                }
            }
        }
        if (donorSum < donorQuest + e.bonus) {
            bits |= DV_DONOR_AMOUNT;
        } else {
            uint256 commission = donorSum - donorQuest - e.bonus;
            if (commission != e.scaledA && commission != e.scaledB && commission != e.scaledC) bits |= DV_DONOR_AMOUNT;
        }
        if (gnrusSum != gnrusQuest) bits |= DV_GNRUS_EXTRA;
        if (donorWrites != 1 + donorLevelQuests) bits |= DV_DONOR_WRITES;
    }

    /// @notice A GNRUS ticket donation (purchaseOrderFor(3, ...)) by a tracked donor, with a zero
    ///         code, a live custom affiliate code, or arbitrary bytes. The Game replaces the code
    ///         with the donor's ID in every case.
    function donate(uint256 donorSeed, uint256 ticketsSeed, uint256 codeMode) external action {
        uint256 i = _i(donorSeed);
        address donor = actors[i];
        uint256 q = bound(ticketsSeed, 1, 20) * 400; // under 100 tickets: no biggest-buy record
        (uint24 lvl, bool jp, , , uint256 price) = game.purchaseInfo_g1027();
        uint256 cost = (price * q) / 400;
        bytes32 code;
        uint256 mode = codeMode % 3;
        if (mode == 1) code = bytes32("FCAZERO");
        else if (mode == 2) code = keccak256(abi.encode(codeMode));
        DonationExpect memory e;
        e.donorId = ids[i];
        e.bonus = ((q * 250) / 100) / 10 + (q >= 4_000 ? (q * 1_000) / 8_000 : 0);
        uint256 fresh = (cost * 1_000) / price;
        uint256 rate = uint256(lvl) + 1 <= 3 ? 2_500 : 2_000;
        e.scaledA = (fresh * rate) / 10_000;
        e.scaledB = jp ? (((fresh * 7) / 5) * rate) / 10_000 : e.scaledA;
        e.scaledC = jp ? (((fresh * 3) / 2) * rate) / 10_000 : e.scaledA;
        vm.deal(donor, donor.balance + cost);
        uint256 t0 = coin.totalSupply();
        _drain();
        vm.prank(donor);
        try game.purchaseOrderFor{value: cost}(GNRUS_ID, q, 0, code, MintPaymentKind.DirectEth, false) {
            VmSafe.Log[] memory logs = vm.getRecordedLogs();
            _ingest(logs, t0, false);
            uint256 bits = donationViolations(logs, e);
            if (bits != 0) {
                _fail(vDonation, "donation FLIP routing", bits, e.donorId, _stakeTo(logs, e.donorId));
                ++vDonation;
            }
            ++hits[mode == 0 ? H_DONATION_NOCODE : H_DONATION_CODE];
            if (i == 1 || i == 2) ++hits[H_DONATION_UPLINE]; // actors 1 and 2 have uplines
        } catch {
            _drain();
        }
    }

    struct NoCodeExpect {
        uint256 bonus; // GNRUS's own purchase bonus
        uint256 recycle; // the 10% recycle bonus of a claimable-funded buy of 3+ tickets
        uint256 share; // the recycled-rate (5%) commission, owed to VAULT or sDGNRS
    }

    uint256 internal constant DV_NOCODE_GNRUS = 16;
    uint256 internal constant DV_NOCODE_SHARE = 32;

    /// @notice Oracle for a GNRUS purchase WITHOUT a donor code (the Vault's Degenesis budget buying
    ///         GNRUS tickets): ordinary routing. GNRUS keeps its purchase bonus (plus the recycle
    ///         bonus and its own quest rewards); the commission goes to VAULT or sDGNRS (no
    ///         referrer); nobody else is credited.
    function noCodeViolations(VmSafe.Log[] memory logs, NoCodeExpect memory e) public pure returns (uint256 bits) {
        uint256 gnrusSum;
        uint256 gnrusQuest;
        uint256 protocolSum;
        uint256 protocolQuest;
        for (uint256 k; k < logs.length; ++k) {
            VmSafe.Log memory lg = logs[k];
            if (lg.topics.length < 2) continue;
            bytes32 sig = lg.topics[0];
            uint32 id = uint32(uint256(lg.topics[1]));
            if (lg.emitter == ContractAddresses.COINFLIP && sig == STAKE_SIG) {
                (uint256 amt, ) = abi.decode(lg.data, (uint256, uint256));
                if (id == GNRUS_ID) gnrusSum += amt;
                else if (id == 1 || id == 2) protocolSum += amt;
                else if (amt != 0) bits |= DV_OTHER_PAID;
            } else if (lg.emitter == ContractAddresses.QUESTS && (sig == QUEST_SIG || sig == LEVEL_QUEST_SIG)) {
                uint256 reward = sig == QUEST_SIG
                    ? _questReward(lg.data)
                    : _levelQuestReward(lg.data);
                if (id == GNRUS_ID) gnrusQuest += reward;
                else if (id == 1 || id == 2) protocolQuest += reward;
            }
        }
        if (gnrusSum != e.bonus + e.recycle + gnrusQuest) bits |= DV_NOCODE_GNRUS;
        if (protocolSum != e.share + protocolQuest) bits |= DV_NOCODE_SHARE;
    }

    function _questReward(bytes memory data) private pure returns (uint256 reward) {
        (, , reward) = abi.decode(data, (uint8, uint32, uint256));
    }

    function _levelQuestReward(bytes memory data) private pure returns (uint256 reward) {
        (, reward) = abi.decode(data, (uint8, uint256));
    }

    /// @notice The Vault's Degenesis budget buys GNRUS tickets (a GNRUS purchase with a zero code).
    ///         Only reachable once Degenesis built a Vault budget.
    function vaultBuysForGnrus(uint256 ticketsSeed) external action {
        uint256 q = bound(ticketsSeed, 1, 20) * 400;
        (, , , , uint256 price) = game.purchaseInfo_g1027();
        uint256 cost = (price * q) / 400;
        NoCodeExpect memory e;
        e.bonus = ((q * 250) / 100) / 10 + (q >= 4_000 ? (q * 1_000) / 8_000 : 0);
        if (cost >= price * 3) e.recycle = (cost * 1_000) / (price * 10);
        e.share = (((cost * 1_000) / price) * 500) / 10_000;
        uint256 t0 = coin.totalSupply();
        _drain();
        vm.prank(ContractAddresses.OWNER_GOVERNANCE);
        (bool ok, ) = ContractAddresses.VAULT.call(
            abi.encodeWithSignature("spendDegenesis(uint32,bool,uint256,uint256,uint256)", GNRUS_ID, false, q, 0, cost)
        );
        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        if (!ok) return;
        _ingest(logs, t0, false);
        uint256 bits = noCodeViolations(logs, e);
        if (bits != 0) {
            _fail(vDonation, "no-code GNRUS purchase routing", bits, _stakeTo(logs, GNRUS_ID), e.bonus);
            ++vDonation;
        }
        ++hits[H_DONATION_VAULT_NOCODE];
    }

    // ================================================================== mining chain

    /// @dev One gameH.mineFlip step; ingests its logs only if it succeeded.
    function _mineStep() internal returns (bool ok) {
        uint256 before = gameH.ghost_successfulAdvances();
        uint256 t0 = coin.totalSupply();
        _drain();
        gameH.mineFlip(0);
        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        ok = gameH.ghost_successfulAdvances() != before;
        if (ok) {
            _ingest(logs, t0, true);
            ghostRequested = cf.requestedDailyIdx();
        }
    }

    function _fulfill(uint256 word) internal {
        uint256 before = vrfH.ghost_vrfFulfillments();
        uint256 t0 = coin.totalSupply();
        _drain();
        vrfH.fulfillVrf(word);
        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        if (vrfH.ghost_vrfFulfillments() != before) {
            _ingest(logs, t0, true);
            ghostRequested = cf.requestedDailyIdx();
        }
    }

    /// @dev Crank the mining chain. stopFrozen: stop once today's request lands (frozen window).
    ///      stopApplied: stop as soon as today's flip applies while the Game still holds its lock.
    function _crank(uint256 word, bool stopFrozen, bool stopApplied) internal {
        for (uint256 k; k < CRANK_CAP; ++k) {
            if (game.gameOver()) break;
            if (stopFrozen && _frozen()) break;
            if (stopApplied && !_frozen() && game.rngLocked() && k != 0) break;
            // Any outstanding request (the daily word or a mid-day word) is answered: the
            // engine cannot request the next day until the delivered session completes.
            _fulfill(uint256(keccak256(abi.encode(word, k))));
            if (!game.advanceDue() && !game.rngLocked() && game.rngComplete()) break;
            _mineStep();
        }
    }

    /// @notice Move to the next day and run the chain to completion.
    function advanceDay(uint256 word) external action {
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _crank(word, false, false);
    }

    /// @notice Move to the next day and stop once the daily request lands: the flip is frozen.
    function requestOnly(uint256 word) external action {
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _crank(word, true, false);
    }

    /// @notice Finish a pending day; optionally stop right after the flip applies under the lock.
    function finishDay(uint256 word, bool stopAfterApply) external action {
        _crank(word, false, stopAfterApply);
    }

    // ================================================================== width mode

    /// @notice Width mode only: push a tracked player's carry (rolling) or bank near uint128 max.
    ///         The model adopts the injected value; every later step must stay exact with the
    ///         saturating clamps and must never revert.
    function injectWidth(uint256 actorSeed, uint256 gapSeed, bool toCarry) external action {
        if (!widthMode) return;
        uint256 i = _i(actorSeed);
        uint32 id = ids[i];
        uint256 v = MAX128 - bound(gapSeed, 0, 1e30);
        bytes32 s = _stateSlot(id);
        if (toCarry) {
            if (!pos[i].rebuy) return;
            uint256 b = uint256(vm.load(address(cf), bytes32(uint256(s) + 1)));
            uint256 old = b >> 128;
            vm.store(address(cf), bytes32(uint256(s) + 1), bytes32((b & MAX128) | (v << 128)));
            if (v >= old) gInjected += v - old;
            else gEjected += old - v;
            pos[i].carry = v;
        } else {
            uint256 a = uint256(vm.load(address(cf), s));
            uint256 old = uint128(a);
            vm.store(address(cf), s, bytes32((a & ~MAX128) | v));
            if (v >= old) gInjected += v - old;
            else gEjected += old - v;
            pos[i].bank = v;
        }
        ++hits[H_INJECT];
    }
}
