// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";
import {GameTimeLib} from "../../../contracts/libraries/GameTimeLib.sol";
import {MockVRFCoordinator} from "../../../contracts/mocks/MockVRFCoordinator.sol";
import {MockLinkToken} from "../../../contracts/mocks/MockLinkToken.sol";
import {BoxOrderLib} from "../../helpers/BoxOrderLib.sol";
import {GameSlots, GameSlotKeys, CrapsSlots} from "../../helpers/GameSlots.sol";

interface IWidWwxrp {
    function bucketInfo(uint24 day, uint8 bucket) external view returns (uint256, uint256, uint32);
    function entryAt(uint24 day, uint8 bucket, uint32 index) external view returns (uint32 id, uint256 cum);
    function bucketOf(uint24 day, uint32 id) external view returns (uint8);
    function incineratorInfo(uint24 bracket) external view returns (uint256, uint32);
    function incineratorEntryAt(uint24 bracket, uint32 index) external view returns (uint32 id, uint256 cum);
}

interface IWidQuests {
    function marketBetGates(address player, uint24 lvl) external view returns (bool, bool, uint32);
}

interface IWidCraps {
    function betWordOf(uint256 betId) external view returns (uint256);
    function currentBonusSlot() external view returns (uint24 day, uint256 period, uint256 slot);
    function highMultForDay(uint24 day) external view returns (uint256);
}

interface IWidBalance {
    function balanceOf(address) external view returns (uint256);
}

/// @title WalletIdTruthHandler -- every wallet-ID allocator and cache on the real protocol
/// @notice Drives each door that allocates a Game wallet ID or fills a contract's ID cache, from a
///         seeded actor set plus fresh addresses minted on demand (so first contact happens on
///         every door), and records every `WalletRegistered` the Game emits. `checkAll` is the
///         suite-wide ID-truth oracle of LOOTBOX-ORDER-QUEUE-PLAN section 0: the canonical pair
///         (wallet-table element and `mintPacked_` bits 224..255) agrees in both directions, IDs
///         are contiguous with exactly one registration each, and every cached or stored ID in
///         Coinflip, Craps, Affiliate, sDGNRS, WWXRP, Parimutuel, Jackpots and the Decimator equals
///         the canonical ID of its key.
/// @dev Storage roots of the other contracts come from `scripts/layout/golden/<Contract>.json`;
///      `PhaseESlotCounts.t.sol` and the suite's non-vacuity test pin them at runtime.
///      Two reachability shortcuts, both confined to one call: the Decimator window opens only at
///      levels x4/x99, so `f_decimatorBurn` opens it for `level + 1` the way the advance does (window
///      flag and the round's `openedDay`) and shuts the flag after the burn; the growth market opens
///      only in a jackpot phase at level >= 1, so `pm_placeBet` mocks `growthState(0)` as open for
///      that one bet when the real market is shut. Neither touches an ID path.
contract WalletIdTruthHandler is Test {
    // ------------------------------------------------------------------ wiring
    DegenerusGame public immutable game;
    MockVRFCoordinator public immutable vrf;
    MockLinkToken public immutable link;

    address internal constant GAME = ContractAddresses.GAME;
    address internal constant COINFLIP = ContractAddresses.COINFLIP;
    address internal constant COIN = ContractAddresses.COIN;
    address internal constant CRAPS = ContractAddresses.CRAPS;
    address internal constant AFFILIATE = ContractAddresses.AFFILIATE;
    address internal constant WWXRP = ContractAddresses.WWXRP;
    address internal constant PARIMUTUEL = ContractAddresses.PARIMUTUEL;
    address internal constant SDGNRS = ContractAddresses.SDGNRS;
    address internal constant DGNRS = ContractAddresses.DGNRS;
    address internal constant VAULT = ContractAddresses.VAULT;
    address internal constant GNRUS = ContractAddresses.GNRUS;
    address internal constant QUESTS = ContractAddresses.QUESTS;
    address internal constant JACKPOTS = ContractAddresses.JACKPOTS;
    address internal constant ADMIN = ContractAddresses.ADMIN;

    // ------------------------------------------------------------------ storage roots (goldens)
    uint256 internal constant CF_PLAYER_STATE = 2; // Coinflip.playerState
    uint256 internal constant CF_ID_SHIFT = 184; // PlayerCoinflipState.id: slot 0, byte offset 23
    uint256 internal constant CR_ID_SHIFT = 85; // CrapsPreferenceLib.ID_SHIFT
    uint256 internal constant CR_BOARD_MASK = uint256(0xFFFFF) << 64;
    uint256 internal constant CR_INITIALIZED = uint256(1) << 84;
    uint256 internal constant AFF_CODE = 0; // DegenerusAffiliate._affiliateCode
    uint256 internal constant AFF_EARNED = 1; // affiliateCoinEarned[lvl][ownerId]
    uint256 internal constant AFF_REFERRAL = 2; // playerReferralCode
    uint256 internal constant AFF_LEVEL_SCORE = 3; // _levelScore
    uint256 internal constant SD_BATCH_PLAYERS = 9; // sDGNRS._batchPlayers (uint256[][2] at 9, 10)
    uint256 internal constant SD_DAY_VALUE = 11; // sDGNRS._redemptionDayValue
    uint256 internal constant SD_ID_SHIFT = 152;
    uint256 internal constant PM_COUNTS = 0; // DegenerusParimutuel.growthCounts
    uint256 internal constant PM_LANES = 2; // DegenerusParimutuel.growthSideLanes
    uint256 internal constant JP_BAF_TOP = 1; // DegenerusJackpots.bafTop
    uint256 internal constant DEC_WINDOW_BIT = (GameSlots.DECIMATOR_FLAGS_OFFSET * 8); // DEC_WINDOW_OPEN = 1

    bytes32 internal constant WALLET_REGISTERED = keccak256("WalletRegistered(uint32,address)");
    bytes32 internal constant DEC_BURN_RECORDED =
        keccak256("DecBurnRecorded(address,uint24,uint64,uint256,uint256,uint256,uint32)");
    bytes32 internal constant DRAW_ENTERED =
        keccak256("DrawEntered(uint24,address,uint8,uint32,uint256,uint256,uint256)");
    bytes32 internal constant SLIP_PLACED = keccak256("CrapsSlipPlaced(uint32,uint256)");

    uint256 internal constant MAX_FRESH = 48;
    uint256 internal constant CAP = 512;

    // ------------------------------------------------------------------ actors and keys
    address[] public actors;
    address[] public keys;
    mapping(address => bool) public isKey;
    uint256 public freshCount;
    /// @dev operator => players that approved it (Game operator approvals made through the handler)
    mapping(address => address[]) internal _approversOf;

    // ------------------------------------------------------------------ registration ghosts
    uint32[] public regIds;
    address[] public regOwners;
    uint256 public nonPayingRegs;
    string public nonPayingAction;

    // ------------------------------------------------------------------ stored-ID ghosts
    bytes32[] public codes;
    mapping(bytes32 => address) public codeCreator;

    struct WxEntry {
        uint24 day;
        uint8 bucket;
        uint32 index;
        address entrant;
    }

    struct PmBet {
        uint24 round;
        uint8 side;
        uint32 index;
        address bettor;
    }

    struct Slip {
        uint256 betId;
        uint32 playerId;
    }

    struct DecEntry {
        uint24 lvl;
        uint64 entryId;
        address burner;
    }

    WxEntry[] internal _wx;
    PmBet[] internal _pm;
    uint24[] internal _pmRounds;
    mapping(uint24 => bool) internal _pmRoundSeen;
    Slip[] internal _slips;
    DecEntry[] internal _dec;

    // ------------------------------------------------------------------ coverage
    uint256 public constant N_ACTIONS = 43;
    string[N_ACTIONS] internal _names;
    uint256[N_ACTIONS] public calls;
    uint256[N_ACTIONS] public oks;
    uint256[N_ACTIONS] public regsBy;
    mapping(uint256 => bytes4[]) internal _revSels;
    mapping(uint256 => mapping(bytes4 => uint256)) public revCount;
    uint256 public ghost_levels;

    /// @dev Gambling burns that took: (beneficiary, batch), so claims target live claims.
    address[] internal _burners;
    uint32[] internal _burnBatches;

    constructor(DegenerusGame game_, MockVRFCoordinator vrf_, MockLinkToken link_, address[] memory seeded) {
        game = game_;
        vrf = vrf_;
        link = link_;
        _initNames();
        _addKey(VAULT);
        _addKey(SDGNRS);
        _addKey(GNRUS);
        _addKey(GAME);
        _addKey(COINFLIP);
        _addKey(CRAPS);
        _addKey(AFFILIATE);
        _addKey(WWXRP);
        _addKey(DGNRS);
        _addKey(ContractAddresses.CREATOR);
        for (uint256 i; i < seeded.length; ++i) {
            actors.push(seeded[i]);
            _addKey(seeded[i]);
        }
        // Every registration since the suite started recording (Game construction included).
        _ingest(true, false, type(uint256).max);
    }

    /// @notice Record the logs a test produced outside the handler (since its last `recordLogs`).
    ///         Not a fuzz target.
    function ingest() external {
        _ingest(true, false, type(uint256).max);
    }

    // =====================================================================================
    // Plumbing
    // =====================================================================================

    function _addKey(address k) internal {
        if (isKey[k]) return;
        isKey[k] = true;
        keys.push(k);
    }

    /// @dev A brand-new address holding ETH, FLIP, WWXRP, LINK and DGNRS but no wallet ID.
    function _fresh() internal returns (address a) {
        a = address(uint160(uint256(keccak256(abi.encode("wallet-id-truth", freshCount++)))));
        vm.deal(a, 300 ether);
        vm.startPrank(GAME);
        (bool ok1,) = COIN.call(abi.encodeWithSignature("mintForGame(address,uint256)", a, 5_000_000));
        (bool ok2,) = WWXRP.call(abi.encodeWithSignature("mintPrize(address,uint256)", a, 200_000));
        vm.stopPrank();
        link.mint(a, 50 ether);
        vm.prank(ContractAddresses.CREATOR);
        (bool ok3,) = DGNRS.call(abi.encodeWithSignature("transfer(address,uint256)", a, 1_000_000 ether));
        ok1;
        ok2;
        ok3;
        actors.push(a);
        _addKey(a);
    }

    /// @dev The acting wallet: a fresh address a quarter of the time (while the budget lasts).
    function _actor(uint256 seed) internal returns (address) {
        if (seed % 4 == 0 && freshCount < MAX_FRESH) return _fresh();
        return actors[(seed >> 2) % actors.length];
    }

    /// @dev A third party: an existing actor, or (a third of the time) a fresh address.
    function _other(uint256 seed) internal returns (address) {
        if (seed % 3 == 0 && freshCount < MAX_FRESH) return _fresh();
        return actors[(seed >> 2) % actors.length];
    }

    /// @dev A player that approved `op` as its Game operator, else `op` itself.
    function _approverOf(address op, uint256 seed) internal view returns (address) {
        address[] storage list = _approversOf[op];
        if (list.length == 0) return op;
        return list[seed % list.length];
    }

    /// @dev An affiliate code: none, default codes of known and brand-new wallets, created custom
    ///      codes, the protocol codes, and the rejected shapes (lock sentinel, forged default word,
    ///      unknown custom code).
    function _code(uint256 sel, address self) internal returns (bytes32) {
        uint256 k = sel % 10;
        if (k == 0) return bytes32(0);
        if (k == 1 || k == 2) return bytes32(uint256(uint160(actors[(sel >> 8) % actors.length])));
        if (k == 3 && freshCount < MAX_FRESH) return bytes32(uint256(uint160(_fresh())));
        if (k == 4 && codes.length != 0) return codes[(sel >> 8) % codes.length];
        if (k == 5) return bytes32("VAULT");
        if (k == 6) return bytes32("DGNRS");
        if (k == 7) return bytes32(uint256(1));
        if (k == 8) {
            return bytes32(uint256(uint160(actors[(sel >> 8) % actors.length])) | (uint256(4 + (sel >> 16) % 8) << 160));
        }
        if (k == 9) return bytes32(uint256(keccak256(abi.encode("unknown", sel))) | (uint256(1) << 255));
        return bytes32(uint256(uint160(self)));
    }

    /// @dev The single dispatch: prank, low-level call (reverts are caught), count, ingest logs.
    function _call(uint256 id, address from, address target, uint256 value, bytes memory data, bool nonPaying)
        internal
        returns (bool ok, bytes memory ret)
    {
        ++calls[id];
        vm.recordLogs();
        if (value > from.balance) value = from.balance;
        vm.prank(from);
        (ok, ret) = target.call{value: value}(data);
        if (ok) {
            ++oks[id];
        } else {
            bytes4 sel = ret.length >= 4 ? bytes4(ret) : bytes4(0);
            if (revCount[id][sel]++ == 0 && _revSels[id].length < 8) _revSels[id].push(sel);
        }
        _ingest(ok, nonPaying, id);
    }

    /// @dev Record the logs of one call. Logs of a reverted call are dropped.
    function _ingest(bool ok, bool nonPaying, uint256 id) internal {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        if (!ok) return;
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory l = logs[i];
            if (l.topics.length == 0) continue;
            bytes32 t0 = l.topics[0];
            if (l.emitter == GAME) {
                if (t0 == WALLET_REGISTERED && l.topics.length == 3) {
                    address owner = address(uint160(uint256(l.topics[2])));
                    regIds.push(uint32(uint256(l.topics[1])));
                    regOwners.push(owner);
                    _addKey(owner);
                    if (id < N_ACTIONS) ++regsBy[id];
                    if (nonPaying && nonPayingRegs++ == 0) nonPayingAction = _names[id];
                } else if (t0 == DEC_BURN_RECORDED && l.topics.length == 4 && _dec.length < CAP) {
                    _dec.push(DecEntry(
                        uint24(uint256(l.topics[2])), uint64(uint256(l.topics[3])), address(uint160(uint256(l.topics[1])))
                    ));
                }
            } else if (l.emitter == WWXRP && t0 == DRAW_ENTERED && l.topics.length == 3 && _wx.length < CAP) {
                (uint8 bucket, uint32 index,,,) = abi.decode(l.data, (uint8, uint32, uint256, uint256, uint256));
                _wx.push(WxEntry(uint24(uint256(l.topics[1])), bucket, index, address(uint160(uint256(l.topics[2])))));
            } else if (l.emitter == CRAPS && t0 == SLIP_PLACED && l.topics.length == 2 && _slips.length < CAP) {
                uint256 bet = abi.decode(l.data, (uint256));
                _slips.push(Slip((bet >> 32) & type(uint128).max, uint32(uint256(l.topics[1]))));
            }
        }
    }

    function _crapsDay() internal view returns (uint24 day) {
        (bool ok, bytes memory r) = CRAPS.staticcall(abi.encodeWithSignature("currentBonusSlot()"));
        if (ok && r.length >= 96) (day,,) = abi.decode(r, (uint24, uint256, uint256));
    }

    function _validChips(uint256 seed) internal pure returns (uint32) {
        if (seed % 4 == 0) return 0;
        uint32 pass = uint32(seed % 4);
        uint32 six = uint32((seed >> 2) % 4);
        uint32 eight = uint32((seed >> 4) % 2);
        return pass | (six << 9) | (eight << 12);
    }

    function _multiple(uint256 seed) internal view returns (uint16) {
        if (seed % 3 != 0) return 1;
        (bool ok, bytes memory r) = CRAPS.staticcall(abi.encodeWithSignature("highMultForDay(uint24)", _crapsDay()));
        return ok && r.length >= 32 ? uint16(abi.decode(r, (uint256))) : 1;
    }

    function _price() internal view returns (uint256 priceWei) {
        (,,,, priceWei) = game.purchaseInfo();
    }

    // =====================================================================================
    // Game doors (paying)
    // =====================================================================================

    function g_purchase(uint256 a, uint256 oSeed, uint256 qty, uint256 box, uint256 codeSel, uint256 kindSel)
        external
    {
        address p = _actor(a);
        address buyer = oSeed % 4 == 0 ? _approverOf(p, oSeed >> 2) : p;
        qty = bound(qty, 400, 4000);
        uint256 boxAmt = box % 3 == 0 ? 0 : bound(box, 0.01 ether, 0.3 ether);
        uint256 cost = _price() * qty / 400 + boxAmt;
        MintPaymentKind kind = kindSel % 5 == 0 ? MintPaymentKind.Combined : MintPaymentKind.DirectEth;
        uint256 value = cost + (kindSel % 7 == 0 ? 0.003 ether : 0);
        _call(0, p, GAME, value, abi.encodeWithSelector(
            DegenerusGame.purchase.selector, buyer, qty, boxAmt == 0 ? 0 : BoxOrderLib.boCustomFloor(boxAmt),
            _code(codeSel, p), kind, kindSel % 11 == 0), false);
    }

    function g_boxOnly(uint256 a, uint256 amt, uint256 codeSel) external {
        address p = _actor(a);
        amt = bound(amt, 0.01 ether, 0.5 ether);
        _call(1, p, GAME, amt, abi.encodeWithSelector(
            DegenerusGame.purchase.selector, p, uint256(0), BoxOrderLib.boCustomFloor(amt), _code(codeSel, p),
            MintPaymentKind.DirectEth, false), false);
    }

    function g_presaleBox(uint256 a, uint256 amtSeed) external {
        address p = _actor(a);
        uint256 credit = game.presaleBoxCreditOf(p);
        uint256 amount = credit > 0.01 ether ? 0.01 ether + amtSeed % (credit - 0.01 ether + 1) : 0.01 ether;
        _call(2, p, GAME, amount, abi.encodeWithSignature("buyPresaleBox(address,uint256)", p, amount), false);
    }

    function g_degenerette(uint256 a, uint256 oSeed, uint256 cSeed, uint256 aSeed, uint256 sSeed, uint256 sym)
        external
    {
        address p = _actor(a);
        address player = oSeed % 3 == 0 ? _other(oSeed >> 2) : p; // a gift when the player is someone else
        uint8 currency = uint8(cSeed % 2);
        uint128 amt;
        uint8 spins;
        uint256 value;
        if (currency == 0) {
            amt = uint128(0.005 ether * (1 + aSeed % 10));
            spins = uint8(1 + sSeed % 5);
            value = uint256(amt) * spins;
        } else {
            amt = uint128(100 + aSeed % 5_000);
            spins = uint8(1 + sSeed % 15);
        }
        _call(3, p, GAME, value, abi.encodeWithSignature(
            "placeDegeneretteBet(address,uint8,uint128,uint8,uint8)", player, currency, amt, spins, uint8(sym % 24)), false);
    }

    function g_whalePass(uint256 a, uint256 codeSel, uint256 over) external {
        address p = _actor(a);
        uint256 value = game.level() <= 3 ? 2.4 ether : 4 ether;
        _call(4, p, GAME, value + (over % 5 == 0 ? 0.01 ether : 0), abi.encodeWithSignature(
            "purchaseWhalePass(address,uint256,bytes32)", p, uint256(1), _code(codeSel, p)), false);
    }

    function g_lazyPass(uint256 a, uint256 codeSel) external {
        address p = _actor(a);
        _call(5, p, GAME, 0.24 ether, abi.encodeWithSignature("purchaseLazyPass(address,bytes32)", p, _code(codeSel, p)), false);
    }

    function g_deityPass(uint256 a, uint256 codeSel, uint256 symSeed) external {
        address p = _actor(a);
        uint256 sold = uint8(uint256(vm.load(GAME, bytes32(GameSlots.DEITY_PASS_SALES))));
        if (sold > 12) return;
        uint256 price = 24 ether + (sold * (sold + 1) * 1 ether) / 2;
        _call(6, p, GAME, price, abi.encodeWithSignature(
            "purchaseDeityPass(address,uint8,bytes32)", p, uint8(symSeed % 32), _code(codeSel, p)), false);
    }

    function g_redeemFlip(uint256 a, uint256 qty) external {
        address p = _actor(a);
        _call(7, p, GAME, 0, abi.encodeWithSignature("redeemFlip(address,uint256)", p, 400 * (1 + qty % 4)), false);
    }

    function g_subscribe(uint256 a, uint256 v) external {
        address p = _actor(a);
        _call(8, p, GAME, bound(v, 0.01 ether, 1 ether), abi.encodeWithSignature(
            "subscribe(address,bool,bool,uint8,address)", p, false, true, uint8(1), address(0)), false);
    }

    // =====================================================================================
    // Game doors (non-paying: the beneficiary must already hold an ID)
    // =====================================================================================

    function g_depositAfking(uint256 a, uint256 oSeed, uint256 v) external {
        address p = _actor(a);
        address beneficiary = oSeed % 2 == 0 ? p : _other(oSeed >> 1);
        _call(9, p, GAME, bound(v, 1, 1 ether), abi.encodeWithSignature("depositAfkingFunding(address)", beneficiary), true);
    }

    function g_plainEth(uint256 a, uint256 v) external {
        address p = _actor(a);
        _call(10, p, GAME, bound(v, 1, 1 ether), "", true);
    }

    function g_claimWinnings(uint256 a) external {
        address p = _actor(a);
        _call(11, p, GAME, 0, abi.encodeWithSignature("claimWinnings(address)", p), true);
    }

    function g_approve(uint256 a, uint256 oSeed) external {
        address p = _actor(a);
        address op = _other(oSeed);
        if (op == p) return;
        (bool ok,) = _call(12, p, GAME, 0, abi.encodeWithSignature("setOperatorApproval(address,bool)", op, true), true);
        if (ok && _approversOf[op].length < 16) _approversOf[op].push(p);
    }

    // =====================================================================================
    // Coinflip
    // =====================================================================================

    /// @param mode 0 self, 1 operator (for a player that approved the caller), 2 gift
    function cf_deposit(uint256 a, uint256 mode, uint256 oSeed, uint256 amt) external {
        address p = _actor(a);
        address player = p;
        uint256 m = mode % 3;
        if (m == 1) player = _approverOf(p, oSeed);
        else if (m == 2) player = _other(oSeed);
        _call(13, p, COINFLIP, 0, abi.encodeWithSignature(
            "depositCoinflip(address,uint256)", player, bound(amt, 100, 50_000)), false);
    }

    function cf_claim(uint256 a, uint256 amt) external {
        address p = _actor(a);
        _call(14, p, COINFLIP, 0, abi.encodeWithSignature(
            "claimCoinflips(address,uint256)", p, amt % 2 == 0 ? type(uint256).max : amt % 100_000), true);
    }

    function cf_autoRebuy(uint256 a, bool enabled, uint256 takeProfit) external {
        address p = _actor(a);
        _call(15, p, COINFLIP, 0, abi.encodeWithSignature(
            "setCoinflipAutoRebuy(address,bool,uint256)", p, enabled, takeProfit % 1_000_000), true);
    }

    // =====================================================================================
    // FLIP decimator burn (window opened for this call only; see the contract notice)
    // =====================================================================================

    function f_decimatorBurn(uint256 a, uint256 amt, uint256 chipSeed) external {
        address p = _actor(a);
        bool forced = _openDecWindow();
        _call(16, p, COIN, 0, abi.encodeWithSignature(
            "decimatorBurn(address,uint256,uint32)", address(0), bound(amt, 2_000, 200_000), _validChips(chipSeed)), false);
        if (forced) _shutDecWindow();
    }

    function _openDecWindow() internal returns (bool forced) {
        if (game.decWindow() || game.gameOver()) return false;
        uint24 lvl = game.level() + 1;
        bytes32 roundSlot = keccak256(abi.encode(uint256(lvl), GameSlots.DEC_BATTLE_ROUNDS));
        uint256 round = uint256(vm.load(GAME, roundSlot));
        if ((round >> 224) & 0xFF != 0) return false; // sealed (phase != 0)
        if ((round >> 200) & 0xFFFFFF == 0) {
            uint256 day = game.currentDayView();
            vm.store(GAME, roundSlot, bytes32(round | (day << 200)));
        }
        uint256 w = uint256(vm.load(GAME, bytes32(GameSlots.DECIMATOR_FLAGS)));
        vm.store(GAME, bytes32(GameSlots.DECIMATOR_FLAGS), bytes32(w | (uint256(1) << DEC_WINDOW_BIT)));
        return true;
    }

    function _shutDecWindow() internal {
        uint256 w = uint256(vm.load(GAME, bytes32(GameSlots.DECIMATOR_FLAGS)));
        vm.store(GAME, bytes32(GameSlots.DECIMATOR_FLAGS), bytes32(w & ~(uint256(1) << DEC_WINDOW_BIT)));
    }

    // =====================================================================================
    // Craps (paying doors register; board saves and pass management require an ID)
    // =====================================================================================

    function cr_setBoard(uint256 a, uint256 chipSeed) external {
        _call(17, _actor(a), CRAPS, 0, abi.encodeWithSignature("setPreferredBoard(uint32)", _validChips(chipSeed)), true);
    }

    function cr_bonusBattle(uint256 a, uint256 period, uint256 chipSeed, uint256 multSeed) external {
        _call(18, _actor(a), CRAPS, 0, abi.encodeWithSignature(
            "enterBonusBattle(uint256,uint32,uint16)", period % 7, _validChips(chipSeed), _multiple(multSeed)), false);
    }

    function cr_bonusDay(uint256 a, uint256 chipSeed, uint256 multSeed) external {
        _call(19, _actor(a), CRAPS, 0, abi.encodeWithSignature(
            "enterBonusDay(uint32,uint16)", _validChips(chipSeed), _multiple(multSeed)), false);
    }

    function cr_futureDays(uint256 a, uint256 off, uint256 count, bool high, uint256 chipSeed) external {
        _call(20, _actor(a), CRAPS, 0, abi.encodeWithSignature(
            "buyFutureCrapsDays(uint24,uint8,bool,uint32)", _crapsDay() + 1 + uint24(off % 3), uint8(1 + count % 2), high,
            _validChips(chipSeed)), false);
    }

    function cr_applyPasses(uint256 a, uint256 off, bool high, uint256 chipSeed) external {
        _call(21, _actor(a), CRAPS, 0, abi.encodeWithSignature(
            "applyCrapsPasses(uint24,uint8,bool,uint32)", _crapsDay() + 1 + uint24(off % 3), uint8(1), high,
            _validChips(chipSeed)), true);
    }

    function cr_amendSlip(uint256 a, uint256 pick, uint256 chipSeed) external {
        address p = _actor(a);
        uint256 betId = _slips.length == 0 ? pick : _slips[pick % _slips.length].betId;
        if (_slips.length != 0 && pick % 4 != 0) {
            uint32 owner = _slips[pick % _slips.length].playerId;
            if (owner != 0) p = address(uint160(_element(owner)));
        }
        _call(22, p, CRAPS, 0, abi.encodeWithSignature("amendSlip(uint256,uint32)", betId, _validChips(chipSeed)), true);
    }

    function cr_convert(uint256 a, uint256 n) external {
        _call(23, _actor(a), CRAPS, 0, abi.encodeWithSignature("convertNormalToHigh(uint32)", uint32(1 + n % 2)), true);
    }

    function cr_upgradeReserved(uint256 a, uint256 off) external {
        _call(24, _actor(a), CRAPS, 0, abi.encodeWithSignature(
            "upgradeReservedDay(uint24)", _crapsDay() + 1 + uint24(off % 3)), true);
    }

    function cr_upgradeWindows(uint256 a, uint256 off, uint256 mask) external {
        _call(25, _actor(a), CRAPS, 0, abi.encodeWithSignature(
            "upgradeDayWindows(uint24,uint8)", _crapsDay() + uint24(off % 3), uint8(1 + mask % 63)), false);
    }

    // =====================================================================================
    // Affiliate
    // =====================================================================================

    function af_createCode(uint256 a, uint256 s, uint256 kick) external {
        address p = _actor(a);
        bytes32 code = bytes32(uint256(keccak256(abi.encode("wid-code", s))) | (uint256(1) << 255));
        (bool ok,) = _call(26, p, AFFILIATE, 0, abi.encodeWithSignature(
            "createAffiliateCode(bytes32,uint8)", code, uint8(kick % 26)), false);
        if (ok && codes.length < 64) {
            codes.push(code);
            codeCreator[code] = p;
        }
    }

    function af_referPlayer(uint256 a, uint256 codeSel) external {
        address p = _actor(a);
        _call(27, p, AFFILIATE, 0, abi.encodeWithSignature("referPlayer(bytes32)", _code(codeSel, p)), false);
    }

    function af_claim(uint256 a, uint256 sSeed) external {
        address p = _actor(a);
        address[] memory subs = new address[](1);
        subs[0] = sSeed % 2 == 0 ? p : actors[sSeed % actors.length];
        _call(28, p, AFFILIATE, 0, abi.encodeWithSignature("claim(address[])", subs), true);
    }

    // =====================================================================================
    // WWXRP / Parimutuel / Admin
    // =====================================================================================

    function wx_enter(uint256 a, uint256 amt) external {
        _call(29, _actor(a), WWXRP, 0, abi.encodeWithSignature("enter(uint256)", bound(amt, 25, 5_000)), false);
    }

    function wx_claim(uint256 a, uint256 daySel, uint256 idx) external {
        uint24 today = GameTimeLib.currentDayIndex();
        uint24 day = today > 2 ? today - 1 - uint24(daySel % 2) : 0;
        _call(30, _actor(a), WWXRP, 0, abi.encodeWithSignature("claim(uint24,uint32)", day, uint32(idx % 8)), true);
    }

    function pm_placeBet(uint256 a, uint256 oSeed, bool over) external {
        address p = _actor(a);
        address player = oSeed % 4 == 0 ? _approverOf(p, oSeed >> 2) : p;
        (,,, uint24 round, bool open,) = game.growthState(0);
        bool mocked;
        if (!open || round == 0) {
            if (game.gameOver()) return;
            round = round == 0 ? 1 : round;
            vm.mockCall(GAME, abi.encodeWithSignature("growthState(uint24)", uint24(0)),
                abi.encode(uint256(0), uint256(0), uint256(0), round, true, uint8(0)));
            mocked = true;
        }
        uint8 side = over ? 1 : 2;
        uint256 counts = uint256(vm.load(PARIMUTUEL, keccak256(abi.encode(uint256(round), PM_COUNTS))));
        uint256 index = over ? uint128(counts) : counts >> 128;
        (bool ok,) = _call(31, p, PARIMUTUEL, 0, abi.encodeWithSignature("placeBet(address,bool)", player, over), false);
        if (mocked) vm.clearMockedCalls();
        if (ok && _pm.length < CAP) {
            _pm.push(PmBet(round, side, uint32(index), player));
            if (!_pmRoundSeen[round]) {
                _pmRoundSeen[round] = true;
                _pmRounds.push(round);
            }
        }
    }

    function adm_donateLink(uint256 a, uint256 amt) external {
        address p = _actor(a);
        amt = bound(amt, 1e15, 5 ether);
        if (link.balanceOf(p) < amt) link.mint(p, amt);
        _call(32, p, address(link), 0, abi.encodeWithSignature("transferAndCall(address,uint256,bytes)", ADMIN, amt, ""), false);
    }

    // =====================================================================================
    // sDGNRS (gambling burns and claims need an existing ID)
    // =====================================================================================

    function s_burn(uint256 a, uint256 amtSeed) external {
        address p = _actor(a);
        uint256 bal = IWidBalance(SDGNRS).balanceOf(p);
        uint32 batch = _openBatch();
        (bool ok,) = _call(33, p, SDGNRS, 0, abi.encodeWithSignature("burn(uint256)", 1e18 + amtSeed % (bal / 1000 + 1)), true);
        _noteBurn(ok, p, batch);
    }

    function s_burnWrapped(uint256 a, uint256 amtSeed) external {
        address p = _actor(a);
        uint256 bal = IWidBalance(DGNRS).balanceOf(p);
        uint32 batch = _openBatch();
        (bool ok,) = _call(34, p, SDGNRS, 0, abi.encodeWithSignature("burnWrapped(uint256)", 1e18 + amtSeed % (bal / 1000 + 1)), true);
        _noteBurn(ok, p, batch);
    }

    /// @dev Claim a recorded gambling burn (or, a quarter of the time, any batch for anyone).
    function s_claim(uint256 a, uint256 sel) external {
        address p;
        uint32 batch;
        if (_burners.length != 0 && sel % 4 != 0) {
            uint256 k = (sel >> 2) % _burners.length;
            p = _burners[k];
            batch = _burnBatches[k];
        } else {
            p = _actor(a);
            uint32 open = _openBatch();
            batch = open > (sel % 3) ? open - uint32(sel % 3) : 0;
        }
        _call(35, p, SDGNRS, 0, abi.encodeWithSignature("claimRedemption(address,uint32)", p, batch), true);
    }

    function _openBatch() internal view returns (uint32) {
        return uint32(uint256(vm.load(SDGNRS, bytes32(0))) >> 224);
    }

    function _noteBurn(bool ok, address p, uint32 batch) internal {
        if (ok && _burners.length < 128) {
            _burners.push(p);
            _burnBatches.push(batch);
        }
    }

    // =====================================================================================
    // Progress (mineFlip keepers may be registered on their first paid bounty)
    // =====================================================================================

    function prog_mineFlip(uint256 a) external {
        address keeper = _actor(a);
        uint24 lvl = game.level();
        vm.fee(1 gwei);
        _call(36, keeper, GAME, 0, abi.encodeWithSignature("mineFlip()"), false);
        vm.fee(0);
        if (game.level() > lvl) ghost_levels += game.level() - lvl;
    }

    function prog_fulfillVrf(uint256 word) external {
        _fulfill(37, word);
    }

    function prog_warp(uint256 delta) external {
        ++calls[38];
        ++oks[38];
        vm.warp(block.timestamp + bound(delta, 1 minutes, 2 days));
    }

    function prog_driveDay(uint256 a, uint256 word) external {
        address keeper = _actor(a);
        uint24 lvl = game.level();
        vm.warp(block.timestamp + 1 days);
        vm.fee(1 gwei);
        for (uint256 i; i < 40; ++i) {
            _fulfill(39, uint256(keccak256(abi.encode(word, i))));
            (bool ok,) = _call(39, keeper, GAME, 0, abi.encodeWithSignature("mineFlip()"), false);
            if (!ok && !_fulfill(39, uint256(keccak256(abi.encode(word, i, "r"))))) break;
        }
        vm.fee(0);
        if (game.level() > lvl) ghost_levels += game.level() - lvl;
    }

    /// @notice Drive the next day from its first minute, so the period-0 craps window (the only
    ///         time a whole-day ticket sells) is open afterwards.
    function prog_driveDayAligned(uint256 a, uint256 word) external {
        address keeper = _actor(a);
        uint24 lvl = game.level();
        uint256 ts = block.timestamp;
        vm.warp(ts - ((ts - 82_620) % 1 days) + 1 days + 60);
        vm.fee(1 gwei);
        for (uint256 i; i < 40; ++i) {
            _fulfill(42, uint256(keccak256(abi.encode(word, i, "aligned"))));
            (bool ok,) = _call(42, keeper, GAME, 0, abi.encodeWithSignature("mineFlip()"), false);
            if (!ok && !_fulfill(42, uint256(keccak256(abi.encode(word, i, "aligned-r"))))) break;
        }
        vm.fee(0);
        if (game.level() > lvl) ghost_levels += game.level() - lvl;
    }

    function prog_bigBuy(uint256 a, uint256 eth) external {
        address p = actors[a % actors.length];
        uint256 priceWei = _price();
        eth = bound(eth, 1 ether, 40 ether);
        if (priceWei == 0) return;
        _call(40, p, GAME, eth, abi.encodeWithSelector(
            DegenerusGame.purchase.selector, p, eth * 400 / priceWei, uint256(0), bytes32(0), MintPaymentKind.DirectEth, false),
            false);
    }

    function prog_topUp(uint256 a) external {
        ++calls[41];
        ++oks[41];
        address p = actors[a % actors.length];
        vm.startPrank(GAME);
        (bool ok1,) = COIN.call(abi.encodeWithSignature("mintForGame(address,uint256)", p, 1_000_000));
        (bool ok2,) = WWXRP.call(abi.encodeWithSignature("mintPrize(address,uint256)", p, 50_000));
        vm.stopPrank();
        ok1;
        ok2;
        if (p.balance < 50 ether) vm.deal(p, 200 ether);
    }

    function _fulfill(uint256 id, uint256 word) internal returns (bool ok) {
        uint256 reqId = vrf.lastRequestId();
        if (reqId == 0) return false;
        (,, bool fulfilled) = vrf.pendingRequests(reqId);
        if (fulfilled) return false;
        (ok,) = _call(id, address(this), address(vrf), 0,
            abi.encodeWithSelector(MockVRFCoordinator.fulfillRandomWords.selector, reqId, word | 1), true);
    }

    // =====================================================================================
    // The oracle
    // =====================================================================================

    function _element(uint32 id) internal view returns (uint256) {
        return uint256(vm.load(GAME, GameSlotKeys.walletElement(id)));
    }

    function _keyOf(uint32 id) internal view returns (address) {
        return address(uint160(_element(id)));
    }

    function _fwd(address key) internal view returns (uint32) {
        return uint32(uint256(vm.load(GAME, GameSlotKeys.mintPacked(key))) >> 224);
    }

    function _tableLength() internal view returns (uint256) {
        return uint256(vm.load(GAME, bytes32(GameSlots.WALLETS)));
    }

    /// @dev True when `id` is an allocated ID whose canonical pair agrees in both directions.
    function _registered(uint32 id) internal view returns (bool) {
        return id != 0 && id < _tableLength() && _fwd(_keyOf(id)) == id;
    }

    function _fail(string memory tag, string memory what, address key, uint256 a, uint256 b) internal pure {
        revert(string.concat(tag, ": ", what, " key=", vm.toString(key), " got=", vm.toString(a), " want=", vm.toString(b)));
    }

    /// @notice The suite-wide ID-truth invariant. Reverts with a tagged reason on the first breach.
    function checkAll() external view {
        _checkRegistry();
        _checkKeys();
        _checkCodes();
        _checkEarnings();
        _checkWwxrp();
        _checkParimutuel();
        _checkCraps();
        _checkSdgnrsBatches();
        _checkDecimator();
        _checkBafBoard();
        if (nonPayingRegs != 0) {
            revert(string.concat("NONPAYING: a non-paying door registered a wallet: ", nonPayingAction));
        }
    }

    /// @dev Canonical pair, one registration per ID, contiguous IDs, protocol constants.
    function _checkRegistry() internal view {
        uint256 n = regIds.length;
        if (_tableLength() != n + 1) _fail("REGISTRY", "table length != registrations + 1", address(0), _tableLength(), n + 1);
        if (_element(0) != 0) _fail("REGISTRY", "element 0 assigned", address(0), _element(0), 0);
        if (n < 3 || regOwners[0] != VAULT || regOwners[1] != SDGNRS || regOwners[2] != GNRUS) {
            revert("REGISTRY: protocol IDs are not VAULT 1, SDGNRS 2, GNRUS 3");
        }
        for (uint256 i; i < n; ++i) {
            uint32 id = regIds[i];
            address owner = regOwners[i];
            if (id != i + 1) _fail("REGISTRY", "IDs not contiguous (or an ID registered twice)", owner, id, i + 1);
            if (owner == address(0)) _fail("REGISTRY", "zero owner", owner, id, 0);
            if (_keyOf(id) != owner) _fail("REGISTRY", "element(id) != key", owner, uint160(_keyOf(id)), uint160(owner));
            if (_fwd(owner) != id) _fail("REGISTRY", "mintPacked_[key] >> 224 != id (ID split)", owner, _fwd(owner), id);
        }
    }

    /// @dev Every known key: reverse direction, and every per-contract cache of the key.
    function _checkKeys() internal view {
        uint256 len = _tableLength();
        for (uint256 i; i < keys.length; ++i) {
            address k = keys[i];
            uint32 id = _fwd(k);
            if (id != 0) {
                if (id >= len) _fail("KEYS", "forward ID past the table", k, id, len);
                if (_keyOf(id) != k) _fail("KEYS", "element at the forward ID does not hold the key", k, uint160(_keyOf(id)), uint160(k));
            }
            _checkKeyCaches(k, id);
        }
    }

    function _checkKeyCaches(address k, uint32 id) internal view {
        // Coinflip slot A
        uint32 c = uint32(uint256(vm.load(COINFLIP, keccak256(abi.encode(k, CF_PLAYER_STATE)))) >> CF_ID_SHIFT);
        if (c != 0 && c != id) _fail("COINFLIP", "slot A cached ID != canonical", k, c, id);
        // Craps address word: board, INITIALIZED and the ID cache; pass lanes stay zero
        uint256 cw = uint256(vm.load(CRAPS, keccak256(abi.encode(k, CrapsSlots.PASS_CREDITS))));
        uint32 cc = uint32(cw >> CR_ID_SHIFT);
        if (cc != 0 && cc != id) _fail("CRAPS", "address word cached ID != canonical", k, cc, id);
        if (cw & type(uint64).max != 0) _fail("CRAPS", "address word holds pass lanes", k, cw & type(uint64).max, 0);
        if (cc != 0 && cw & CR_INITIALIZED != 0) {
            uint256 iw = uint256(vm.load(CRAPS, keccak256(abi.encode(uint256(cc), CrapsSlots.PASS_CREDITS_BY_ID))));
            if (iw & CR_INITIALIZED == 0 || iw & CR_BOARD_MASK != cw & CR_BOARD_MASK) {
                _fail("CRAPS", "saved board differs between address word and ID word", k, iw & CR_BOARD_MASK, cw & CR_BOARD_MASK);
            }
        }
        // sDGNRS forward word
        uint32 s = uint32(uint256(vm.load(SDGNRS, keccak256(abi.encode(k, SD_DAY_VALUE)))) >> SD_ID_SHIFT);
        if (s != 0 && s != id) _fail("SDGNRS", "forward word cached ID != canonical", k, s, id);
        // Affiliate referral word
        uint256 w = uint256(vm.load(AFFILIATE, keccak256(abi.encode(k, AFF_REFERRAL))));
        if (w > 1 && w < (uint256(1) << 160)) _fail("AFFILIATE", "referral word in the sentinel range", k, w, 0);
        if (w >= (uint256(1) << 160) && w < (uint256(1) << 192)) {
            address owner = address(uint160(w));
            uint32 oid = uint32(w >> 160);
            if (oid == 0 || oid != _fwd(owner)) _fail("AFFILIATE", "default-code referral word owner ID != canonical", owner, oid, _fwd(owner));
        }
        // Quests piggyback: mayBet implies a nonzero ID equal to the canonical one
        (bool mayBet,, uint32 gid) = IWidQuests(QUESTS).marketBetGates(k, 1);
        if (gid != id) _fail("QUESTS", "marketBetGates ID != canonical", k, gid, id);
        if (mayBet && id == 0) _fail("QUESTS", "mayBet without a wallet ID", k, 0, 1);
    }

    /// @dev The referrer ID a cache of `k`'s first hop must hold, from Game's canonical IDs.
    ///      `stable` is false for an unset referral, which must never be cached.
    function _canonRef(address k) internal view returns (bool stable, uint32 id) {
        uint256 w = uint256(vm.load(AFFILIATE, keccak256(abi.encode(k, AFF_REFERRAL))));
        if (w == 0) return (false, 1);
        if (w == 1) return (true, 1);
        if (w < (uint256(1) << 192)) return (true, _fwd(address(uint160(w))));
        bytes32 c = bytes32(w);
        if (c == bytes32("VAULT")) return (true, 1);
        if (c == bytes32("DGNRS")) return (true, 2);
        address creator = codeCreator[c];
        if (creator != address(0)) return (true, _fwd(creator));
        return (true, uint32(uint256(vm.load(AFFILIATE, keccak256(abi.encode(c, AFF_CODE))))));
    }

    /// @dev An upline cache pair (`cache` = valid bits 64/65 over upline1 [0:32) and upline2
    ///      [32:64)) for the owner whose key is `ownerKey`.
    function _checkUplines(string memory tag, address ownerKey, uint256 cache) internal view {
        uint32 u1 = uint32(cache);
        uint32 u2 = uint32(cache >> 32);
        if (cache & (uint256(1) << 64) != 0) {
            (bool stable, uint32 want) = _canonRef(ownerKey);
            if (!stable) _fail(tag, "upline1 cached from an unset referral", ownerKey, u1, 0);
            if (u1 != want || !_registered(u1)) _fail(tag, "upline1 cache != canonical referrer", ownerKey, u1, want);
            if (cache & (uint256(1) << 65) != 0) {
                (bool stable2, uint32 want2) = _canonRef(_keyOf(u1));
                if (!stable2) _fail(tag, "upline2 cached from an unset referral", ownerKey, u2, 0);
                if (u2 != want2 || !_registered(u2)) _fail(tag, "upline2 cache != canonical referrer", ownerKey, u2, want2);
            } else if (u2 != 0) {
                _fail(tag, "upline2 set without its valid bit", ownerKey, u2, 0);
            }
        } else if (cache & (uint256(1) << 65) != 0 || u1 != 0 || u2 != 0) {
            _fail(tag, "upline cache without upline1 valid", ownerKey, cache, 0);
        }
    }

    /// @dev Custom code info (protocol codes and every code the handler created).
    function _checkCodes() internal view {
        _checkCode(bytes32("VAULT"), VAULT, 1);
        _checkCode(bytes32("DGNRS"), SDGNRS, 2);
        for (uint256 i; i < codes.length; ++i) {
            address creator = codeCreator[codes[i]];
            _checkCode(codes[i], creator, _fwd(creator));
        }
    }

    function _checkCode(bytes32 code, address ownerKey, uint32 wantOwner) internal view {
        bytes32 slot = keccak256(abi.encode(code, AFF_CODE));
        uint256 w = uint256(vm.load(AFFILIATE, slot));
        if (w >> 112 != 0) _fail("AFFCODE", "code info spills past bit 112", ownerKey, w >> 112, 0);
        if (uint256(vm.load(AFFILIATE, bytes32(uint256(slot) + 1))) != 0) {
            _fail("AFFCODE", "code info uses a second slot", ownerKey, 1, 0);
        }
        uint32 ownerId = uint32(w);
        uint256 flags = (w >> 104) & 0xFF;
        if (flags & 1 != 0) _fail("AFFCODE", "runtime code left pending", ownerKey, flags, 0);
        if (ownerId == 0 || ownerId != wantOwner) _fail("AFFCODE", "code owner ID != canonical", ownerKey, ownerId, wantOwner);
        uint256 cache = uint256(uint32(w >> 40)) | (uint256(uint32(w >> 72)) << 32) | (((flags >> 1) & 3) << 64);
        _checkUplines("AFFCODE", ownerKey, cache);
    }

    /// @dev Earnings-word upline caches and level leaders, every level the run can have touched.
    function _checkEarnings() internal view {
        uint256 len = _tableLength();
        uint256 maxLvl = uint256(game.level()) + 2;
        for (uint256 lvl; lvl <= maxLvl; ++lvl) {
            bytes32 inner = keccak256(abi.encode(lvl, AFF_EARNED));
            for (uint32 id = 1; id < len; ++id) {
                uint256 w = uint256(vm.load(AFFILIATE, keccak256(abi.encode(uint256(id), inner))));
                uint256 cache = w >> 128;
                if (cache == 0) continue;
                if (cache >> 66 != 0) _fail("AFFEARN", "earnings word spills past bit 194", _keyOf(id), cache >> 66, 0);
                _checkUplines("AFFEARN", _keyOf(id), cache);
            }
            uint32 leader = uint32(uint256(vm.load(AFFILIATE, keccak256(abi.encode(lvl, AFF_LEVEL_SCORE)))) >> 224);
            if (leader != 0 && !_registered(leader)) _fail("AFFLEAD", "level leader is not a registered ID", address(0), leader, lvl);
        }
    }

    /// @dev Daily draw entries of the live banks and the century incinerator bracket.
    function _checkWwxrp() internal view {
        uint24 today = GameTimeLib.currentDayIndex();
        for (uint24 d = today > 2 ? today - 2 : 0; d <= today; ++d) {
            for (uint8 b; b < 10; ++b) {
                (,, uint32 count) = IWidWwxrp(WWXRP).bucketInfo(d, b);
                for (uint32 i; i < count; ++i) {
                    (uint32 id,) = IWidWwxrp(WWXRP).entryAt(d, b, i);
                    if (!_registered(id)) _fail("WWXRP", "draw entry ID not registered", address(0), id, d);
                    if (IWidWwxrp(WWXRP).bucketOf(d, id) != b) _fail("WWXRP", "entry in a bucket its ID does not hash to", _keyOf(id), b, d);
                }
            }
        }
        for (uint256 i; i < _wx.length; ++i) {
            WxEntry memory e = _wx[i];
            if (e.day + 2 < today) continue;
            (uint32 id,) = IWidWwxrp(WWXRP).entryAt(e.day, e.bucket, e.index);
            if (id != _fwd(e.entrant)) _fail("WWXRP", "entry ID != entrant's canonical ID", e.entrant, id, _fwd(e.entrant));
        }
        uint24 bracket = (game.level() / 100 + 1) * 100;
        (, uint32 n) = IWidWwxrp(WWXRP).incineratorInfo(bracket);
        for (uint32 i; i < n; ++i) {
            (uint32 id,) = IWidWwxrp(WWXRP).incineratorEntryAt(bracket, i);
            if (!_registered(id)) _fail("WWXRP", "incinerator entry ID not registered", address(0), id, bracket);
        }
    }

    function _pmLane(uint24 round, uint8 side, uint256 index) internal view returns (uint32) {
        uint256 key = (uint256(round) << 40) | (uint256(side) << 32) | (index >> 3);
        uint256 word = uint256(vm.load(PARIMUTUEL, keccak256(abi.encode(key, PM_LANES))));
        return uint32(word >> ((index & 7) << 5));
    }

    /// @dev Every lane of every round bet on, and each recorded bet against its bettor.
    function _checkParimutuel() internal view {
        for (uint256 r; r < _pmRounds.length; ++r) {
            uint24 round = _pmRounds[r];
            uint256 counts = uint256(vm.load(PARIMUTUEL, keccak256(abi.encode(uint256(round), PM_COUNTS))));
            for (uint8 side = 1; side <= 2; ++side) {
                uint256 n = side == 1 ? uint128(counts) : counts >> 128;
                for (uint256 i; i < n; ++i) {
                    uint32 id = _pmLane(round, side, i);
                    if (!_registered(id)) _fail("PARIMUTUEL", "side-array lane not a registered ID", address(0), id, round);
                }
            }
        }
        for (uint256 i; i < _pm.length; ++i) {
            PmBet memory b = _pm[i];
            uint32 id = _pmLane(b.round, b.side, b.index);
            if (id != _fwd(b.bettor)) _fail("PARIMUTUEL", "lane ID != bettor's canonical ID", b.bettor, id, _fwd(b.bettor));
        }
    }

    /// @dev Every slip the table announced: stored owner field and the announced ID agree and
    ///      are registered; bits 32..159 stay zero.
    function _checkCraps() internal view {
        for (uint256 i; i < _slips.length; ++i) {
            Slip memory s = _slips[i];
            if (!_registered(s.playerId)) _fail("CRAPSBET", "slip announced an unregistered ID", address(0), s.playerId, s.betId);
            uint256 w = IWidCraps(CRAPS).betWordOf(s.betId);
            if (w == 0) continue;
            if (uint32(w) != s.playerId) _fail("CRAPSBET", "stored bet owner != announced ID", _keyOf(s.playerId), uint32(w), s.playerId);
            if ((w >> 32) & type(uint128).max != 0) _fail("CRAPSBET", "bet word bits 32..159 nonzero", _keyOf(s.playerId), w, 0);
        }
    }

    /// @dev sDGNRS batch beneficiaries: `address | id << 160`, the ID canonical for the address.
    function _checkSdgnrsBatches() internal view {
        for (uint256 p; p < 2; ++p) {
            uint256 root = SD_BATCH_PLAYERS + p;
            uint256 n = uint256(vm.load(SDGNRS, bytes32(root)));
            uint256 base = uint256(keccak256(abi.encode(root)));
            if (n > 256) n = 256;
            for (uint256 i; i < n; ++i) {
                uint256 e = uint256(vm.load(SDGNRS, bytes32(base + i)));
                address a = address(uint160(e));
                uint32 id = uint32(e >> 160);
                if (id == 0 || id != _fwd(a)) _fail("SDGNRS", "batch beneficiary ID != canonical", a, id, _fwd(a));
            }
        }
    }

    /// @dev Decimator entries: owner ID in bits 0..31 (32..159 zero), canonical for the burner.
    function _checkDecimator() internal view {
        for (uint256 i; i < _dec.length; ++i) {
            DecEntry memory e = _dec[i];
            uint256 key = (uint256(e.lvl) << 64) | e.entryId;
            uint256 w = uint256(vm.load(GAME, keccak256(abi.encode(key, GameSlots.DEC_BATTLE_ENTRIES))));
            if (w == 0) continue;
            if (uint32(w) != _fwd(e.burner) || uint32(w) == 0) _fail("DECIMATOR", "entry owner ID != burner's canonical ID", e.burner, uint32(w), _fwd(e.burner));
            if ((w >> 32) & type(uint128).max != 0) _fail("DECIMATOR", "entry bits 32..159 nonzero", e.burner, w, 0);
        }
    }

    /// @dev Jackpots BAF board lanes (`score96 | id << 96`, two per word) hold registered IDs.
    function _checkBafBoard() internal view {
        uint256 maxLvl = uint256(game.level()) + 2;
        for (uint256 lvl; lvl <= maxLvl; ++lvl) {
            uint256 base = uint256(keccak256(abi.encode(lvl, JP_BAF_TOP)));
            for (uint256 wI; wI < 2; ++wI) {
                uint256 word = uint256(vm.load(JACKPOTS, bytes32(base + wI)));
                for (uint256 half; half < 2; ++half) {
                    uint256 entry = (word >> (half * 128)) & type(uint128).max;
                    if (entry == 0) continue;
                    uint32 id = uint32(entry >> 96);
                    if (!_registered(id)) _fail("BAF", "board lane ID not registered", address(0), id, lvl);
                }
            }
        }
    }

    // =====================================================================================
    // Views for the suite and its reports
    // =====================================================================================

    function regCount() external view returns (uint256) {
        return regIds.length;
    }

    function keyCount() external view returns (uint256) {
        return keys.length;
    }

    function slipCount() external view returns (uint256) {
        return _slips.length;
    }

    function pmBetCount() external view returns (uint256) {
        return _pm.length;
    }

    function wxEntryCount() external view returns (uint256) {
        return _wx.length;
    }

    function decEntryCount() external view returns (uint256) {
        return _dec.length;
    }

    function codeCount() external view returns (uint256) {
        return codes.length;
    }

    function actionName(uint256 id) external view returns (string memory) {
        return _names[id];
    }

    function revertSelectors(uint256 id) external view returns (bytes4[] memory) {
        return _revSels[id];
    }

    function _initNames() internal {
        _names[0] = "g_purchase";
        _names[1] = "g_boxOnly";
        _names[2] = "g_presaleBox";
        _names[3] = "g_degenerette";
        _names[4] = "g_whalePass";
        _names[5] = "g_lazyPass";
        _names[6] = "g_deityPass";
        _names[7] = "g_redeemFlip";
        _names[8] = "g_subscribe";
        _names[9] = "g_depositAfking";
        _names[10] = "g_plainEth";
        _names[11] = "g_claimWinnings";
        _names[12] = "g_approve";
        _names[13] = "cf_deposit";
        _names[14] = "cf_claim";
        _names[15] = "cf_autoRebuy";
        _names[16] = "f_decimatorBurn";
        _names[17] = "cr_setBoard";
        _names[18] = "cr_bonusBattle";
        _names[19] = "cr_bonusDay";
        _names[20] = "cr_futureDays";
        _names[21] = "cr_applyPasses";
        _names[22] = "cr_amendSlip";
        _names[23] = "cr_convert";
        _names[24] = "cr_upgradeReserved";
        _names[25] = "cr_upgradeWindows";
        _names[26] = "af_createCode";
        _names[27] = "af_referPlayer";
        _names[28] = "af_claim";
        _names[29] = "wx_enter";
        _names[30] = "wx_claim";
        _names[31] = "pm_placeBet";
        _names[32] = "adm_donateLink";
        _names[33] = "s_burn";
        _names[34] = "s_burnWrapped";
        _names[35] = "s_claim";
        _names[36] = "prog_mineFlip";
        _names[37] = "prog_fulfillVrf";
        _names[38] = "prog_warp";
        _names[39] = "prog_driveDay";
        _names[40] = "prog_bigBuy";
        _names[41] = "prog_topUp";
        _names[42] = "prog_driveDayAligned";
    }
}
