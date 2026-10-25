// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DegenesisBoonReference as BoonRef} from "./DegenesisBoonReference.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenesisDeployProtocol} from "./DeployProtocol.sol";
import {GameSlots, GameSlotKeys} from "../../helpers/GameSlots.sol";
import {BoxOrderLib} from "../../helpers/BoxOrderLib.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";
import {sDGNRS} from "../../../contracts/sDGNRS.sol";
import {EntropyLib} from "../../../contracts/libraries/EntropyLib.sol";
import {FlipRoundLib} from "../../../contracts/libraries/FlipRoundLib.sol";
import {CrapsPriceLib} from "../../../contracts/libraries/CrapsPriceLib.sol";
import {PriceLookupLib} from "../../../contracts/libraries/PriceLookupLib.sol";
import {GameTimeLib} from "../../../contracts/libraries/GameTimeLib.sol";

/// @title DegenesisHarness -- Degenesis-timeline fixture, state readers and a reference model
/// @notice Deploys on day index 1. Credit is earned through ordinary lootbox purchases, orders go
///         through game.buyDegenesisBox, and days are driven through mineFlip with mock VRF
///         fulfilment. `_refOutcome` re-implements the module's per-order outcome from the spec
///         formulas so suites compare the contract's DegenesisOrderResolved fields against it.
abstract contract DegenesisHarness is DegenesisDeployProtocol {
    // ---- spec / module constants (mirrored) ----
    uint256 internal constant UNIT = 0.0001 ether;
    uint256 internal constant MIN_ORDER = 0.01 ether;
    uint256 internal constant MAX_UNITS = (uint256(1) << 38) - 1;
    uint256 internal constant T_EARLY = 20_000_000_000 * 1e12;
    uint256 internal constant T_LATE = 10_000_000_000 * 1e12;
    uint256 internal constant K_UNITS = 460_000;
    uint256 internal constant BONUS_WINDOW = 6 hours;
    uint256 internal constant LOW_BASE = 14_098;
    uint256 internal constant LOW_STEP = 1158;
    uint256 internal constant HIGH_BASE = 74_534;
    uint256 internal constant HIGH_STEP = 22_890;
    uint256 internal constant HIGH_PASS_CAP = 12;
    uint256 internal constant PRICE_COIN_UNIT = 1000;
    uint256 internal constant ORDER_DOMAIN = 0x446567656e657369734f72646572;
    uint256 internal constant CATEGORY_TAG = 0x44656743617465676f7279;
    uint256 internal constant SIZE_TAG = 0x44656753697a65;
    uint256 internal constant PASS_TAG = 0x5061737353696465;
    uint256 internal constant FLIP_ROUND_TAG = 0x466c6970526f756e64;
    uint256 internal constant BOX_PASS_ROUND_TAG = 0x50617373526f756e64;
    uint32 internal constant SDGNRS_ID = 2;
    uint8 internal constant ACTION_REQUEST_DAILY = 16;
    uint8 internal constant ACTION_DEGENESIS_SETTLE = 20;

    bytes32 internal constant SIG_RESOLVED =
        keccak256("DegenesisOrderResolved(uint32,uint8,uint32,uint256,uint256,uint256,uint256,uint32,uint32)");
    bytes32 internal constant SIG_BUY = keccak256("DegenesisBuy(uint32,uint8,uint32,uint256,uint256)");
    bytes32 internal constant SIG_SPLIT = keccak256("DegenesisCohortSplit(uint8,uint256)");
    bytes32 internal constant SIG_PRICED = keccak256("DegenesisCohortPriced(uint8,uint256,uint256,uint24)");
    bytes32 internal constant SIG_CLOSED = keccak256("DegenesisCohortClosed(uint8,uint256)");
    bytes32 internal constant SIG_BURNED = keccak256("DegenesisInventoryBurned(uint256)");

    /// @dev One resolved order as the contract announced it, or as the reference predicts it.
    struct Res {
        uint32 id;
        uint8 day;
        uint32 index;
        uint256 amount;
        uint256 flip;
        uint256 dgnrs;
        uint256 wwxrp;
        uint32 normalPasses;
        uint32 highPasses;
        uint24 boonTypes;
    }

    uint256 internal lastFulfilledReq;
    uint256 internal vrfNonce;

    function setUp() public virtual {
        _deployProtocol();
    }

    // =====================================================================
    // Clock
    // =====================================================================

    /// @dev Timestamp at which day index `d` begins (boundary 0 under patchForFoundry).
    function _dayStart(uint24 d) internal pure returns (uint256) {
        return uint256(d - 1) * 1 days + GameTimeLib.JACKPOT_RESET_TIME;
    }

    /// @dev Day index of Degenesis day `c`.
    function _dayOf(uint256 c) internal pure returns (uint24) {
        return uint24(GameTimeLib.DEGENESIS_START_DAY + c - 1);
    }

    function _warpTo(uint24 d, uint256 secs) internal {
        vm.warp(_dayStart(d) + secs);
    }

    // =====================================================================
    // Players, credit and orders
    // =====================================================================

    function _player(string memory name) internal returns (address p) {
        p = makeAddr(name);
        vm.deal(p, 1_000_000 ether);
    }

    /// @dev Earn `credit` of Degenesis credit through a real ordinary purchase: one custom
    ///      lootbox of 4 x credit, paid in fresh ETH.
    function _earnCredit(address p, uint256 credit) internal {
        uint256 spend = credit * 4;
        if (p.balance < spend) vm.deal(p, spend + 1 ether);
        vm.prank(p);
        game.purchase{value: spend}(0, 0, BoxOrderLib.boCustom(spend), bytes32(0), MintPaymentKind.DirectEth, false);
    }

    /// @dev Write `credit` straight into degenesisCredit[id] (vm.store). Used only where a real
    ///      purchase of 4x the credit is impractical (per-order bound tests, multi-million ETH).
    function _seedCredit(address p, uint256 credit) internal {
        uint32 id = game.walletIdOf_g3120(p);
        if (id == 0) id = _giveWalletId(p);
        vm.store(address(game), keccak256(abi.encode(uint256(id), GameSlots.DEGENESIS_CREDIT)), bytes32(credit));
        assertEq(game.degenesisCreditOf(p), credit, "seedCredit: slot mismatch");
    }

    function _buy(address p, uint256 amount) internal {
        if (p.balance < amount) vm.deal(p, amount + 1 ether);
        vm.prank(p);
        game.buyDegenesisBox{value: amount}(0, amount);
    }

    // =====================================================================
    // Driving days
    // =====================================================================

    /// @dev Run mineFlip until the engine has nothing to do or waits on a word; a pending
    ///      request is fulfilled with `vrfWord` (nonzero) first.
    function _drive(uint256 vrfWord) internal {
        for (uint256 i; i < 400; ++i) {
            _fulfillPending(vrfWord);
            try game.mineFlip(0) {} catch (bytes memory reason) {
                bytes4 sel = bytes4(reason);
                if (reason.length == 4 && sel == bytes4(keccak256("RngNotReady()"))) {
                    if (_fulfillPending(vrfWord)) continue;
                    return;
                }
                if (reason.length == 4 && sel == bytes4(keccak256("NoWork()"))) return;
                assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
            }
        }
        fail("drive: engine did not settle");
    }

    /// @dev Fulfil the latest VRF request if it is still open. Returns whether it fulfilled.
    function _fulfillPending(uint256 vrfWord) internal returns (bool) {
        uint256 req = mockVRF.lastRequestId();
        if (req == 0 || req == lastFulfilledReq) return false;
        (,, bool fulfilled) = mockVRF.pendingRequests(req);
        lastFulfilledReq = req;
        if (fulfilled) return false;
        if (vrfWord == 0) vrfWord = uint256(keccak256(abi.encode("degenesis-vrf", req, ++vrfNonce)));
        mockVRF.fulfillRandomWords(req, vrfWord);
        return true;
    }

    /// @dev Open at the reset so purchase offsets measure elapsed cohort time.
    function _driveDay(uint24 d, uint256 vrfWord) internal {
        _warpTo(d, 0);
        _drive(vrfWord);
    }

    /// @dev Step the engine up to (not into) the day's request: the preparation stages run on a
    ///      gas budget below the request bound, so the next call's first action is the request.
    function _stepToRequest() internal {
        for (uint256 i; i < 200; ++i) {
            _fulfillPending(0);
            if (game.nextMinerAction() == ACTION_REQUEST_DAILY) return;
            try game.mineFlip{gas: 3_000_000}(0) {} catch {
                game.mineFlip(0);
            }
        }
        fail("stepToRequest: request never next");
    }

    /// @dev From a day start: step to the request, run it alone, fulfil it with `vrfWord`.
    function _requestOnly(uint256 vrfWord) internal {
        _stepToRequest();
        game.mineFlip(0);
        _fulfillPending(vrfWord);
    }

    /// @dev One mineFlip on `gasBudget`, escalating x2 up to four times when a budget cannot fund
    ///      the first checkpoint, then a full call. Returns false once the engine reports NoWork /
    ///      RngNotReady. Small budgets keep stage-to-stage carry-over (into settlement) small.
    function _mineStep(uint256 gasBudget) internal returns (bool) {
        _fulfillPending(0);
        for (uint256 k; k < 5; ++k) {
            try game.mineFlip{gas: gasBudget << k}(0) {
                return true;
            } catch (bytes memory reason) {
                if (_isIdle(reason)) return false;
            }
        }
        try game.mineFlip(0) {
            return true;
        } catch (bytes memory reason) {
            if (_isIdle(reason)) return false;
            assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
        }
    }

    function _isIdle(bytes memory reason) internal pure returns (bool) {
        bytes4 sel = bytes4(reason);
        return reason.length == 4 && (sel == bytes4(keccak256("NoWork()")) || sel == bytes4(keccak256("RngNotReady()")));
    }

    /// @dev Drive on small budgets until the next action is Degenesis settlement (or idle):
    ///      the daily word is applied and every RNG consumer done; settlement may have taken at
    ///      most a few orders on the last step.
    function _driveToSettle() internal {
        for (uint256 i; i < 2000; ++i) {
            _fulfillPending(0);
            if (game.nextMinerAction() == ACTION_DEGENESIS_SETTLE) return;
            if (!_mineStep(2_500_000)) return;
        }
        fail("driveToSettle: no progress");
    }

    /// @dev Write the sDGNRS Degenesis pool balance (vm.store), keeping sDGNRS's own token
    ///      balance equal to the pool sum. Used only for zero-inventory / dust cases that real
    ///      play cannot reach (L = 1.5Q <= R keeps the pool from emptying).
    function _setDegPool(uint256 x) internal {
        uint256 old = _degPool();
        bytes32 balSlot = keccak256(abi.encode(address(sdgnrs), uint256(1)));
        uint256 bal = uint256(vm.load(address(sdgnrs), balSlot));
        vm.store(address(sdgnrs), balSlot, bytes32(bal + x - old));
        uint256 w = uint256(vm.load(address(sdgnrs), bytes32(uint256(4))));
        vm.store(address(sdgnrs), bytes32(uint256(4)), bytes32((w >> 128 << 128) | x));
        assertEq(_degPool(), x, "setDegPool: slot mismatch");
    }

    /// @dev Keep driving whole days from `fromDay` until `degenesisClosed == 7` (at most to day 20).
    function _driveToClose(uint24 fromDay) internal {
        for (uint24 d = fromDay; d < 21; ++d) {
            if (_closed() == 7) return;
            _driveDay(d, 0);
        }
        assertEq(_closed(), 7, "driveToClose: sale never closed");
    }

    // =====================================================================
    // State readers
    // =====================================================================

    function _closed() internal view returns (uint8) {
        return uint8(uint256(vm.load(address(game), bytes32(GameSlots.DEGENESIS_CLOSED))) >> (GameSlots.DEGENESIS_CLOSED_OFFSET * 8));
    }

    function _active() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(GameSlots.DEGENESIS_ACTIVE)));
    }

    function _activeQ() internal view returns (uint256) { return _active() & ((uint256(1) << 80) - 1); }
    function _activePaid() internal view returns (uint256) { return (_active() >> 80) & ((uint256(1) << 80) - 1); }
    function _activeDay() internal view returns (uint24) { return uint24(_active() >> 160); }
    function _activeCursor() internal view returns (uint32) { return uint32(_active() >> 184); }

    function _word() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(GameSlots.DEGENESIS_WORD)));
    }

    function _header(uint256 c) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(c, GameSlots.DEGENESIS_DAYS))));
    }

    function _volumeUnits(uint256 c) internal view returns (uint256) { return uint48(_header(c)); }
    function _count(uint256 c) internal view returns (uint256) { return uint32(_header(c) >> 48); }
    function _split(uint256 c) internal view returns (bool) { return (_header(c) >> 80) & 1 == 1; }

    function _orderSlot(uint256 c, uint256 index) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode((c << 32) | (index / 3), GameSlots.DEGENESIS_ORDERS))));
    }

    function _lane(uint256 c, uint256 index) internal view returns (uint256) {
        return (_orderSlot(c, index) >> ((index % 3) * 85)) & ((uint256(1) << 85) - 1);
    }

    function _vaultBudget() internal view returns (uint256) {
        return uint128(uint256(vm.load(address(game), bytes32(GameSlots.DEGENESIS_VAULT_BUDGET))));
    }

    function _sdgnrsAfking() internal view returns (uint256) {
        return uint256(vm.load(address(game), GameSlotKeys.balances(SDGNRS_ID))) >> 128;
    }

    /// @dev Future pool including the frozen pending buffer (bit 255 of its slot is the sentinel).
    function _futureTotal() internal view returns (uint256 f) {
        f = uint256(vm.load(address(game), bytes32(GameSlots.PRIZE_POOLS_PACKED))) >> 128;
        uint256 slot0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        if ((slot0 >> (GameSlots.PRIZE_POOL_FROZEN_OFFSET * 8)) & 0xff != 0) {
            f += (uint256(vm.load(address(game), bytes32(GameSlots.PRIZE_POOL_PENDING_PACKED))) >> 128)
                & (type(uint128).max >> 1);
        }
    }

    function _degPool() internal view returns (uint256) {
        return sdgnrs.poolBalance(sDGNRS.Pool.Degenesis);
    }

    // =====================================================================
    // Reference model (spec §4, §5; module _degenesisOutcome)
    // =====================================================================

    function _target(uint256 c) internal pure returns (uint256) {
        return c <= 3 ? T_EARLY : T_LATE;
    }

    /// @dev Q = min(floor(2.5T), floor(R * 2 / 3)).
    function _refQ(uint256 c, uint256 pool) internal pure returns (uint256 q) {
        q = _target(c) * 5 / 2;
        uint256 cap = pool * 2 / 3;
        if (cap < q) q = cap;
    }

    /// @dev Unrounded FLIP before the 100-FLIP collapse, from the spec factors:
    ///      ladder bps x base(n)/2 x earlyBonus(s) x K/(K+V), converted at the level-1 price.
    function _refFlipRaw(uint256 units, uint256 flipBps, uint256 day, uint256 secs, uint256 volumeUnits)
        internal
        pure
        returns (uint256)
    {
        uint256 s = secs > BONUS_WINDOW ? BONUS_WINDOW : secs;
        // base(n)/2 = (2.5 - 0.125(n-1)) / 2 = (21 - n) / 16; bonus = 1 + 0.05 (1 - s/21600)
        //   = (453_600 - s) / 432_000; r = K / (K + V).
        return (units * UNIT * PRICE_COIN_UNIT * flipBps * (21 - day) * (453_600 - s) * K_UNITS)
            / (uint256(10_000) * 16 * 432_000 * (K_UNITS + volumeUnits) * PriceLookupLib.priceForLevel(1));
    }

    function _ladderBps(uint256 size) internal pure returns (uint256) {
        uint256 roll = size % 20;
        return roll < 16 ? LOW_BASE + roll * LOW_STEP : HIGH_BASE + (roll - 16) * HIGH_STEP;
    }

    function _seed(uint256 word, uint256 day, uint256 index, uint32 id) internal pure returns (uint256) {
        return EntropyLib.hash3(52, word, index);
    }

    /// @dev Category of an order: 0 = FLIP-valued, 1 = sDGNRS, 2 = WWXRP.
    function _refCategory(uint256 word, uint256 day, uint256 index, uint32 id) internal pure returns (uint256) {
        uint256 cat = EntropyLib.hash2(51, _seed(word, day, index, id)) % 100;
        return cat < 50 ? 0 : cat < 90 ? 1 : 2;
    }

    function _refMultBps(uint256 word, uint256 day, uint256 index, uint32 id) internal pure returns (uint256) {
        return 5000 + EntropyLib.hash2(56, _seed(word, day, index, id)) % 10_001;
    }

    /// @dev Pass-side bit of an order: 1 = a FLIP result denominates into Craps passes.
    function _passBit(uint256 word, uint256 day, uint256 index, uint32 id) internal pure returns (uint256) {
        return EntropyLib.hash2(53, _seed(word, day, index, id)) & 1;
    }

    /// @dev A word under which order (day c, index) of `id` rolls FLIP and keeps it as coin credit.
    function _searchFlipCoin(uint256 c, uint256 index, uint32 id) internal pure returns (uint256 w) {
        for (uint256 i;; ++i) {
            w = uint256(keccak256(abi.encode("flip-coin", c, index, id, i)));
            if (_refCategory(w, c, index, id) == 0 && _passBit(w, c, index, id) == 0) return w;
        }
    }

    /// @dev A word under which order (day c, index) of `id` rolls category `cat` and, for
    ///      sDGNRS, a multiplier of at least `minMult` bps.
    function _searchCategory(uint256 c, uint256 index, uint32 id, uint256 cat, uint256 minMult)
        internal
        pure
        returns (uint256 w)
    {
        for (uint256 i;; ++i) {
            w = uint256(keccak256(abi.encode("category", c, index, id, cat, minMult, i)));
            if (_refCategory(w, c, index, id) == cat && (cat != 1 || _refMultBps(w, c, index, id) >= minMult)) return w;
        }
    }

    /// @dev Expected resolution of one order before any pool clamp (an sDGNRS pay above the
    ///      remaining pool is clamped by transferFromPool; a zero pay turns into WWXRP).
    function _refOutcome(
        uint256 word,
        uint256 day,
        uint256 index,
        uint32 id,
        uint256 units,
        uint256 secs,
        uint256 volumeUnits,
        uint256 q
    ) internal pure returns (Res memory o) {
        o.id = id;
        o.day = uint8(day);
        o.index = uint32(index);
        o.amount = units * UNIT;
        o.boonTypes = BoonRef.selected(o.amount, BoonRef.root(word, day, index));
        uint256 seed = _seed(word, day, index, id);
        uint256 cat = EntropyLib.hash2(51, seed) % 100;
        uint256 size = EntropyLib.hash2(56, seed);
        if (cat < 50) {
            uint256 flipOut = _refFlipRaw(units, _ladderBps(size), day, secs, volumeUnits);
            flipOut = flipOut > FlipRoundLib.FLIP_ROUND_THRESHOLD
                ? FlipRoundLib.roundFlipToHundreds(flipOut, EntropyLib.hash2(55, seed))
                : flipOut;
            if (flipOut == 0) {
                o.wwxrp = 1;
            } else if (EntropyLib.hash2(53, seed) & 1 == 1) {
                bool highPass = flipOut > CrapsPriceLib.HIGH_SWITCH;
                uint256 passUnit = highPass ? CrapsPriceLib.HIGH_VALUE : CrapsPriceLib.NORMAL_VALUE;
                uint256 passCount = flipOut / passUnit;
                uint256 rest;
                if (highPass && passCount >= HIGH_PASS_CAP) {
                    passCount = HIGH_PASS_CAP;
                    rest = flipOut - HIGH_PASS_CAP * CrapsPriceLib.HIGH_VALUE;
                } else {
                    uint256 rem = flipOut % passUnit;
                    if (rem != 0 && EntropyLib.hash2(54, seed) % passUnit < rem) ++passCount;
                }
                flipOut = rest;
                if (passCount == 0) o.wwxrp = 1;
                else if (highPass) o.highPasses = uint32(passCount);
                else o.normalPasses = uint32(passCount);
            }
            o.flip = flipOut;
        } else if (cat < 90) {
            o.dgnrs = (units * q * (5000 + size % 10_001)) / (volumeUnits * 10_000);
            if (o.dgnrs == 0) o.wwxrp = 1;
        } else {
            o.wwxrp = 1;
        }
    }

    // =====================================================================
    // Log decoding
    // =====================================================================

    function _resolved(Vm.Log[] memory logs) internal view returns (Res[] memory out) {
        uint256 n;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics.length > 0 && logs[i].topics[0] == SIG_RESOLVED) ++n;
        }
        out = new Res[](n);
        n = 0;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length == 0 || logs[i].topics[0] != SIG_RESOLVED) continue;
            Res memory r = out[n++];
            r.id = uint32(uint256(logs[i].topics[1]));
            (r.day, r.index, r.amount, r.flip, r.dgnrs, r.wwxrp, r.normalPasses, r.highPasses) =
                abi.decode(logs[i].data, (uint8, uint32, uint256, uint256, uint256, uint256, uint32, uint32));
            assertGt(i, 0, "completion has preceding boon event");
            Vm.Log memory companion = logs[i - 1];
            assertEq(companion.emitter, address(game));
            assertEq(companion.topics[0], keccak256("DegenesisBoonsRolled(uint32,uint8,uint32,uint24)"));
            assertEq(companion.topics[1], logs[i].topics[1]);
            (uint8 day, uint32 index, uint24 types_) = abi.decode(companion.data, (uint8,uint32,uint24));
            assertEq(day, r.day); assertEq(index, r.index); r.boonTypes = types_;
        }
    }

    function _countSig(Vm.Log[] memory logs, bytes32 sig) internal view returns (uint256 n) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics.length > 0 && logs[i].topics[0] == sig) ++n;
        }
    }

    function _assertRes(Res memory got, Res memory want, string memory tag) internal pure {
        assertEq(got.id, want.id, string.concat(tag, ": id"));
        assertEq(got.day, want.day, string.concat(tag, ": day"));
        assertEq(got.index, want.index, string.concat(tag, ": index"));
        assertEq(got.amount, want.amount, string.concat(tag, ": amount"));
        assertEq(got.flip, want.flip, string.concat(tag, ": flip"));
        assertEq(got.dgnrs, want.dgnrs, string.concat(tag, ": dgnrs"));
        assertEq(got.wwxrp, want.wwxrp, string.concat(tag, ": wwxrp"));
        assertEq(got.normalPasses, want.normalPasses, string.concat(tag, ": normal passes"));
        assertEq(got.highPasses, want.highPasses, string.concat(tag, ": high passes"));
        assertEq(got.boonTypes, want.boonTypes, string.concat(tag, ": additional boon draws"));
    }

    /// @dev Reference resolution of every order of cohort `c` from its stored lanes, the given
    ///      word and Q (no pool clamp: callers keep pools far above 1.5Q or check clamps apart).
    function _refCohort(uint256 c, uint256 word, uint256 q) internal view returns (Res[] memory out) {
        uint256 n = _count(c);
        uint256 v = _volumeUnits(c);
        out = new Res[](n);
        for (uint256 i; i < n; ++i) {
            uint256 lane = _lane(c, i);
            out[i] = _refOutcome(word, c, i, uint32(lane), (lane >> 32) & MAX_UNITS, lane >> 70, v, q);
        }
    }
}
