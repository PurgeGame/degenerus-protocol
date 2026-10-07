// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";
import {MockVRFCoordinator} from "../../../contracts/mocks/MockVRFCoordinator.sol";
import {MockStETH} from "../../../contracts/mocks/MockStETH.sol";
import {BoxOrderLib} from "../../helpers/BoxOrderLib.sol";
import {TicketQueueStorage} from "../helpers/TicketQueueStorage.sol";

interface IAnyBalance {
    function balanceOf(address) external view returns (uint256);
}

/// @title AnyInputHandler -- arbitrary-input driver for the player-facing doors no other handler calls
/// @notice Every action takes RAW fuzz arguments. Only the acting actor (index into a fixed actor set)
///         and, where an action carries ETH, msg.value (to the actor's balance) are bounded. Address
///         arguments are drawn from a small pool that includes address(0), every actor, the passive
///         BYSTANDER, CREATOR and the protocol contracts. Each call is a low-level call whose revert is
///         caught (the call is the try/catch), counted per action and per revert selector, and ignored.
///
///         Two deviations from "raw", both to make a door reachable at all: the 4-value payKind enum
///         is folded onto 0..4 (4 = out of range, must fail decode), and the gd_* companions derive
///         a real player's arguments from live state (own seat, own far-future level, open window,
///         nudge quote) so each door's success path is driven too; the raw door stays alongside.
///
///         After EVERY action the handler re-reads the bystander's holdings and records the first
///         decrease it ever sees. The bystander is funded in the suite's setUp through normal flows and
///         never acts afterwards, and it approves no operator, so no action by anyone else may reduce it.
contract AnyInputHandler is Test {
    // ------------------------------------------------------------------ wiring
    DegenerusGame public game;
    MockVRFCoordinator public vrf;
    MockStETH public steth;
    address public bystander;
    address public dgve;
    address public dgvf;

    address internal constant COINFLIP = ContractAddresses.COINFLIP;
    address internal constant COIN = ContractAddresses.COIN;
    address internal constant DGNRS_ = ContractAddresses.DGNRS;
    address internal constant SDGNRS_ = ContractAddresses.SDGNRS;
    address internal constant VAULT_ = ContractAddresses.VAULT;
    address internal constant GNRUS_ = ContractAddresses.GNRUS;
    address internal constant WWXRP_ = ContractAddresses.WWXRP;
    address internal constant SEAT = ContractAddresses.AFKING_SUB_TOKEN;
    address internal constant AFFILIATE = ContractAddresses.AFFILIATE;
    address internal constant PARIMUTUEL = ContractAddresses.PARIMUTUEL;
    address internal constant CRAPS = ContractAddresses.CRAPS;

    address[] public actors;
    address[] public pool;
    address internal currentActor;

    // ------------------------------------------------------------------ action bookkeeping
    uint256 public constant N_ACTIONS = 105;
    string[N_ACTIONS] internal _names;
    uint256[N_ACTIONS] public calls;
    uint256[N_ACTIONS] public oks;
    mapping(uint256 => bytes4[]) internal _revSels;
    mapping(uint256 => mapping(bytes4 => uint256)) public revCount;

    // ------------------------------------------------------------------ bystander tracking
    uint256 public constant N_FIELDS = 12;
    uint256[N_FIELDS] public lastSeen;
    uint256 public bystanderViolations;
    uint256 public violationAction;
    uint256 public violationField;
    uint256 public violationBefore;
    uint256 public violationAfter;
    uint256 public seatId;

    // ------------------------------------------------------------------ progress ghosts
    uint256 public ghost_levels;
    uint256 public ghost_vrf;
    uint256 public ghost_mines;
    uint256 public ghost_gameOver;

    constructor(
        DegenerusGame game_,
        MockVRFCoordinator vrf_,
        MockStETH steth_,
        address[] memory actors_,
        address bystander_,
        uint256 seatId_,
        address dgve_,
        address dgvf_
    ) {
        game = game_;
        vrf = vrf_;
        steth = steth_;
        bystander = bystander_;
        seatId = seatId_;
        dgve = dgve_;
        dgvf = dgvf_;
        pool.push(address(0));
        for (uint256 i; i < actors_.length; ++i) {
            actors.push(actors_[i]);
            pool.push(actors_[i]);
        }
        pool.push(bystander_);
        pool.push(address(game_));
        pool.push(VAULT_);
        pool.push(SDGNRS_);
        pool.push(DGNRS_);
        pool.push(COINFLIP);
        pool.push(COIN);
        pool.push(GNRUS_);
        pool.push(CRAPS);
        pool.push(ContractAddresses.CREATOR);
        _initNames();
        uint256[N_FIELDS] memory h = holdings();
        for (uint256 i; i < N_FIELDS; ++i) lastSeen[i] = h[i];
    }

    // =====================================================================================
    // Plumbing
    // =====================================================================================

    modifier act(uint256 actorSeed) {
        currentActor = actors[actorSeed % actors.length];
        _;
        _checkBystander(_lastId);
    }

    uint256 internal _lastId;

    function _p(uint256 seed) internal view returns (address) {
        return pool[seed % pool.length];
    }

    /// @dev A wallet ID for third-party doors: mostly the ID of a pool address (0 when it holds none, which
    ///      resolves to the caller), sometimes an arbitrary small ID so unallocated IDs are probed too.
    function _id(uint256 seed) internal view returns (uint32) {
        if (seed % 8 == 7) return uint32((seed >> 8) % 64);
        return game.walletIdOf(_p(seed));
    }

    /// @dev Like `_id` but never 0, for doors where 0 reverts (third-party recipients).
    function _idNZ(uint256 seed) internal view returns (uint32 id) {
        id = _id(seed);
        if (id == 0) id = 1;
    }

    function _ids(uint256[] memory seeds) internal view returns (uint32[] memory out) {
        out = new uint32[](seeds.length);
        for (uint256 i; i < seeds.length; ++i) out[i] = _id(seeds[i]);
    }

    /// @dev A seat token `who` holds when it holds one, else a seed-picked token id.
    function _seatFor(address who, uint256 seed) internal view returns (uint256) {
        (bool ok, bytes memory r) = SEAT.staticcall(abi.encodeWithSignature("nextSerial()"));
        uint256 n = ok && r.length >= 32 ? abi.decode(r, (uint256)) : 0;
        for (uint256 i = 1; i <= n; ++i) {
            (bool okO, bytes memory o) = SEAT.staticcall(abi.encodeWithSignature("ownerOf(uint256)", i));
            if (okO && o.length >= 32 && abi.decode(o, (address)) == who) return i;
        }
        return n == 0 ? seed : 1 + seed % n;
    }

    function _ps(uint256[] memory seeds) internal view returns (address[] memory out) {
        out = new address[](seeds.length);
        for (uint256 i; i < seeds.length; ++i) out[i] = _p(seeds[i]);
    }

    function _val(uint256 raw) internal view returns (uint256) {
        uint256 bal = currentActor.balance;
        return bal == 0 ? 0 : raw % (bal + 1);
    }

    /// @dev The single dispatch: prank the actor, low-level call (reverts are caught), count.
    function _call(uint256 id, address target, uint256 value, bytes memory data)
        internal
        returns (bool ok, bytes memory ret)
    {
        _lastId = id;
        ++calls[id];
        vm.prank(currentActor);
        (ok, ret) = target.call{value: value}(data);
        if (ok) {
            ++oks[id];
        } else {
            bytes4 s = ret.length >= 4 ? bytes4(ret) : bytes4(0);
            if (revCount[id][s]++ == 0 && _revSels[id].length < 12) _revSels[id].push(s);
        }
    }

    /// @notice The bystander's tracked holdings, in a fixed field order (see fieldName()).
    function holdings() public view returns (uint256[N_FIELDS] memory h) {
        h[0] = game.afkingFundingOf(bystander);
        h[1] = game.claimableWinningsOf(bystander);
        h[2] = IAnyBalance(COIN).balanceOf(bystander);
        (bool okC, bytes memory r) = COINFLIP.staticcall(abi.encodeWithSignature("previewClaimCoinflips(address)", bystander));
        h[3] = okC && r.length >= 32 ? abi.decode(r, (uint256)) : 0;
        h[4] = IAnyBalance(DGNRS_).balanceOf(bystander);
        h[5] = IAnyBalance(SDGNRS_).balanceOf(bystander);
        h[6] = IAnyBalance(SEAT).balanceOf(bystander);
        (bool okO, bytes memory o) = SEAT.staticcall(abi.encodeWithSignature("ownerOf(uint256)", seatId));
        h[7] = okO && o.length >= 32 && abi.decode(o, (address)) == bystander ? 1 : 0;
        h[8] = IAnyBalance(dgve).balanceOf(bystander);
        h[9] = IAnyBalance(dgvf).balanceOf(bystander);
        h[10] = IAnyBalance(WWXRP_).balanceOf(bystander);
        h[11] = IAnyBalance(ContractAddresses.DEITY_PASS).balanceOf(bystander);
    }

    function fieldName(uint256 i) public pure returns (string memory) {
        string[N_FIELDS] memory n = [
            string("afkingFunding"), "claimableWinnings", "FLIP wallet", "coinflip claimable", "DGNRS", "sDGNRS",
            "AFKing seats", "owns seat", "DGVE shares", "DGVF shares", "WWXRP", "deity passes"
        ];
        return n[i];
    }

    /// @dev The one legitimate non-bystander decrease is the post-game-over final sweep, which zeroes
    ///      every claimable and afking balance by design (claimableWinningsOf reads 0 once swept).
    function _checkBystander(uint256 id) internal {
        uint256[N_FIELDS] memory h = holdings();
        bool swept = game.isFinalSwept();
        for (uint256 i; i < N_FIELDS; ++i) {
            if (h[i] < lastSeen[i] && !(swept && (i == 0 || i == 1))) {
                if (bystanderViolations == 0) {
                    violationAction = id;
                    violationField = i;
                    violationBefore = lastSeen[i];
                    violationAfter = h[i];
                }
                ++bystanderViolations;
            }
            lastSeen[i] = h[i];
        }
    }

    // =====================================================================================
    // Coinflip
    // =====================================================================================

    function cf_deposit(uint256 a, uint256 pSeed, uint256 amount) external act(a) {
        _call(0, COINFLIP, 0, abi.encodeWithSignature("depositCoinflip(uint32,uint256)", _id(pSeed), amount));
    }

    function cf_claim(uint256 a, uint256 pSeed, uint256 amount) external act(a) {
        _call(1, COINFLIP, 0, abi.encodeWithSignature("claimCoinflips(uint32,uint256)", _id(pSeed), amount));
    }

    function cf_claimCarry(uint256 a, uint256 pSeed, uint256 amount) external act(a) {
        _call(2, COINFLIP, 0, abi.encodeWithSignature("claimCoinflipCarry(uint32,uint256)", _id(pSeed), amount));
    }

    function cf_setAutoRebuy(uint256 a, uint256 pSeed, bool enabled, uint256 takeProfit) external act(a) {
        _call(3, COINFLIP, 0, abi.encodeWithSignature("setCoinflipAutoRebuy(uint32,bool,uint256)", _id(pSeed), enabled, takeProfit));
    }

    function cf_setTakeProfit(uint256 a, uint256 pSeed, uint256 takeProfit) external act(a) {
        _call(4, COINFLIP, 0, abi.encodeWithSignature("setCoinflipAutoRebuyTakeProfit(uint32,uint256)", _id(pSeed), takeProfit));
    }

    // =====================================================================================
    // Game
    // =====================================================================================

    function g_purchase(
        uint256 a,
        uint256 bSeed,
        uint256 qty,
        uint256 boxOrder,
        bytes32 code,
        uint8 payKind,
        bool foil,
        uint256 value
    ) external act(a) {
        // payKind is folded onto 0..4 only so the 4-value enum is hit at all: 0..3 are the real kinds,
        // 4 reaches the contract out of range and must fail its ABI decode.
        _call(5, address(game), _val(value), abi.encodeWithSelector(
            DegenerusGame.purchase.selector, _id(bSeed), qty, boxOrder, code, uint256(payKind % 5), foil));
    }

    function g_redeemFlip(uint256 a, uint256 bSeed, uint256 qty) external act(a) {
        _call(6, address(game), 0, abi.encodeWithSignature("redeemFlip(uint32,uint256)", _id(bSeed), qty));
    }

    function g_sellFarFuture(uint256 a, uint256 pSeed, uint32[] calldata levels, uint256[] calldata qtys, uint256[] calldata idxs)
        external
        act(a)
    {
        _call(7, address(game), 0, abi.encodeWithSignature(
            "sellFarFutureEntries(uint32,uint32[],uint256[],uint256[])", _id(pSeed), levels, qtys, idxs));
    }

    function g_buyLootboxAndPresaleBox(
        uint256 a,
        uint256 bSeed,
        uint256 qty,
        uint256 boxOrder,
        bytes32 code,
        uint8 payKind,
        uint256 boxAmount,
        uint256 value
    ) external act(a) {
        _call(8, address(game), _val(value), abi.encodeWithSelector(
            DegenerusGame.buyLootboxAndPresaleBox.selector, _id(bSeed), qty, boxOrder, code, uint256(payKind % 5), boxAmount));
    }

    function g_claimBingo(uint256 a, uint256 pSeed, uint24 lvl, uint8 symbol, uint32[8] calldata slots) external act(a) {
        _call(9, address(game), 0, abi.encodeWithSignature("claimBingo(uint32,uint24,uint8,uint32[8])", _id(pSeed), lvl, symbol, slots));
    }

    function g_claimDeadVrf(uint256 a, uint256 pSeed, uint256[] calldata refs) external act(a) {
        _call(10, address(game), 0, abi.encodeWithSignature("claimDeadVrf(uint32,uint256[])", _id(pSeed), refs));
    }

    function g_claimFoilMatch(uint256 a, uint256 pSeed, uint256 day, uint256 idx) external act(a) {
        _call(11, address(game), 0, abi.encodeWithSignature("claimFoilMatch(uint32,uint256,uint256)", _id(pSeed), day, idx));
    }

    function g_claimFoilMatchMany(uint256 a, uint256[] calldata pSeeds, uint24[] calldata dayList, uint8[] calldata idxs)
        external
        act(a)
    {
        _call(12, address(game), 0, abi.encodeWithSignature(
            "claimFoilMatchMany(uint32[],uint24[],uint8[])", _ids(pSeeds), dayList, idxs));
    }

    function g_claimGoldenTicket(uint256 a, uint256 pSeed, uint24 lvl) external act(a) {
        _call(13, address(game), 0, abi.encodeWithSignature("claimGoldenTicket(uint32,uint24)", _id(pSeed), lvl));
    }

    function g_claimAffiliateDgnrs(uint256 a, uint256 pSeed) external act(a) {
        _call(14, address(game), 0, abi.encodeWithSignature("claimAffiliateDgnrs(uint32)", _id(pSeed)));
    }

    function g_claimAffiliateDgnrsMany(uint256 a, uint256[] calldata pSeeds) external act(a) {
        _call(15, address(game), 0, abi.encodeWithSignature("claimAffiliateDgnrs(uint32[])", _ids(pSeeds)));
    }

    function g_claimWhalePass(uint256 a, uint256 pSeed) external act(a) {
        _call(16, address(game), 0, abi.encodeWithSignature("claimWhalePass(uint32)", _id(pSeed)));
    }

    function g_claimAfkingFlip(uint256 a, uint256[] calldata pSeeds) external act(a) {
        _call(17, address(game), 0, abi.encodeWithSignature("claimAfkingFlip(uint32[])", _ids(pSeeds)));
    }

    function g_withdrawAfking(uint256 a, uint256 amount) external act(a) {
        _call(18, address(game), 0, abi.encodeWithSignature("withdrawAfkingFunding(uint32,uint256)", uint32(0), amount));
    }

    function g_depositAfking(uint256 a, uint256 pSeed, uint256 value) external act(a) {
        _call(19, address(game), _val(value), abi.encodeWithSignature("depositAfkingFunding(uint32)", _id(pSeed)));
    }

    function g_reverseFlip(uint256 a, uint256 expectedCost) external act(a) {
        _call(20, address(game), 0, abi.encodeWithSignature("reverseFlip(uint256)", expectedCost));
    }

    function g_issueDeityBoon(uint256 a, uint256 dSeed, uint256 rSeed, uint8 slot) external act(a) {
        _call(21, address(game), 0, abi.encodeWithSignature("issueDeityBoon(uint32,uint32,uint8)", _id(dSeed), _idNZ(rSeed), slot));
    }

    function g_subscribe(uint256 a, uint256 pSeed, bool drain, bool useTickets, uint8 qty, uint256 fSeed, uint256 value)
        external
        act(a)
    {
        _call(22, address(game), _val(value), abi.encodeWithSignature(
            "subscribe(uint32,bool,bool,uint8,uint32,uint256)", _id(pSeed), drain, useTickets, qty, _id(fSeed), _seatFor(currentActor, fSeed)));
    }

    function g_setOperatorApproval(uint256 a, uint256 oSeed, bool approved) external act(a) {
        _call(23, address(game), 0, abi.encodeWithSignature("setOperatorApproval(uint32,address,bool)", uint32(0), _p(oSeed), approved));
    }

    function g_placeDegeneretteBet(
        uint256 a,
        uint256 pSeed,
        uint8 currency,
        uint128 amountPerSpin,
        uint8 spinCount,
        uint8 symbol,
        uint256 value
    ) external act(a) {
        _call(24, address(game), _val(value), abi.encodeWithSignature(
            "placeDegeneretteBet(uint32,uint8,uint128,uint8,uint8)", _id(pSeed), currency, amountPerSpin, spinCount, symbol));
    }

    function g_claimWinnings(uint256 a, uint256 pSeed) external act(a) {
        _call(25, address(game), 0, abi.encodeWithSignature("claimWinnings(uint32)", _id(pSeed)));
    }

    function g_claimWinningsAmount(uint256 a, uint256 pSeed, uint256 amount) external act(a) {
        _call(26, address(game), 0, abi.encodeWithSignature("claimWinnings(uint32,uint256)", _id(pSeed), amount));
    }

    function g_decurse(uint256 a, uint256 tSeed) external act(a) {
        _call(27, address(game), 0, abi.encodeWithSignature("decurse(uint32)", _id(tSeed)));
    }

    function g_smite(uint256 a, uint256 deityId, uint256 sSeed) external act(a) {
        _call(28, address(game), 0, abi.encodeWithSignature("smite(uint256,uint32)", deityId, _id(sSeed)));
    }

    function g_purchaseWhalePass(uint256 a, uint256 bSeed, uint256 qty, bytes32 code, uint256 value) external act(a) {
        _call(29, address(game), _val(value), abi.encodeWithSignature(
            "purchaseWhalePass(uint32,uint256,bytes32)", _id(bSeed), qty, code));
    }

    function g_purchaseLazyPass(uint256 a, uint256 bSeed, bytes32 code, uint256 value) external act(a) {
        _call(30, address(game), _val(value), abi.encodeWithSignature("purchaseLazyPass(uint32,bytes32)", _id(bSeed), code));
    }

    function g_purchaseDeityPass(uint256 a, uint256 bSeed, uint8 symbolId, bytes32 code, uint256 value) external act(a) {
        _call(31, address(game), _val(value), abi.encodeWithSignature(
            "purchaseDeityPass(uint32,uint8,bytes32)", _id(bSeed), symbolId, code));
    }

    function g_buyPresaleBox(uint256 a, uint256 bSeed, uint256 boxAmount, uint256 value) external act(a) {
        _call(32, address(game), _val(value), abi.encodeWithSignature("buyPresaleBox(uint32,uint256)", _id(bSeed), boxAmount));
    }

    function g_claimWinningsStethFirst(uint256 a) external act(a) {
        _call(33, address(game), 0, abi.encodeWithSignature("claimWinningsStethFirst()"));
    }

    // =====================================================================================
    // FLIP
    // =====================================================================================

    function f_transfer(uint256 a, uint256 toSeed, uint256 amount) external act(a) {
        _call(34, COIN, 0, abi.encodeWithSignature("transfer(address,uint256)", _p(toSeed), amount));
    }

    function f_transferFrom(uint256 a, uint256 fromSeed, uint256 toSeed, uint256 amount) external act(a) {
        _call(35, COIN, 0, abi.encodeWithSignature("transferFrom(address,address,uint256)", _p(fromSeed), _p(toSeed), amount));
    }

    function f_approve(uint256 a, uint256 spSeed, uint256 amount) external act(a) {
        _call(36, COIN, 0, abi.encodeWithSignature("approve(address,uint256)", _p(spSeed), amount));
    }

    function f_decimatorBurn(uint256 a, uint256 pSeed, uint256 amount, uint32 chips) external act(a) {
        _call(37, COIN, 0, abi.encodeWithSignature("decimatorBurn(uint32,uint256,uint32)", _id(pSeed), amount, chips));
    }

    // =====================================================================================
    // DGNRS / sDGNRS / Vault / GNRUS
    // =====================================================================================

    function d_transfer(uint256 a, uint256 toSeed, uint256 amount) external act(a) {
        _call(38, DGNRS_, 0, abi.encodeWithSignature("transfer(address,uint256)", _p(toSeed), amount));
    }

    function d_transferFrom(uint256 a, uint256 fromSeed, uint256 toSeed, uint256 amount) external act(a) {
        _call(39, DGNRS_, 0, abi.encodeWithSignature("transferFrom(address,address,uint256)", _p(fromSeed), _p(toSeed), amount));
    }

    function d_approve(uint256 a, uint256 spSeed, uint256 amount) external act(a) {
        _call(40, DGNRS_, 0, abi.encodeWithSignature("approve(address,uint256)", _p(spSeed), amount));
    }

    function d_burn(uint256 a, uint256 amount) external act(a) {
        _call(41, DGNRS_, 0, abi.encodeWithSignature("burn(uint256)", amount));
    }

    function s_burn(uint256 a, uint256 amount) external act(a) {
        _call(42, SDGNRS_, 0, abi.encodeWithSignature("burn(uint256)", amount));
    }

    function s_burnWrapped(uint256 a, uint256 amount) external act(a) {
        _call(43, SDGNRS_, 0, abi.encodeWithSignature("burnWrapped(uint256)", amount));
    }

    function s_claimRedemption(uint256 a, uint256 pSeed, uint32 batchId) external act(a) {
        _call(44, SDGNRS_, 0, abi.encodeWithSignature("claimRedemption(uint32,uint32)", _id(pSeed), batchId));
    }

    function s_claimParkedRedemption(uint256 a, uint256 pSeed, uint32 batchId) external act(a) {
        _call(45, SDGNRS_, 0, abi.encodeWithSignature("claimParkedRedemption(uint32,uint32)", _id(pSeed), batchId));
    }

    function v_burnEth(uint256 a, uint256 amount) external act(a) {
        _call(46, VAULT_, 0, abi.encodeWithSignature("burnEth(uint256)", amount));
    }

    function v_burnCoin(uint256 a, uint256 amount) external act(a) {
        _call(47, VAULT_, 0, abi.encodeWithSignature("burnCoin(uint256)", amount));
    }

    function gn_burn(uint256 a, uint256 amount) external act(a) {
        _call(48, GNRUS_, 0, abi.encodeWithSignature("burn(uint256)", amount));
    }

    function gn_vote(uint256 a, uint8 slot) external act(a) {
        _call(49, GNRUS_, 0, abi.encodeWithSignature("vote(uint8)", slot));
    }

    // =====================================================================================
    // Parimutuel / Affiliate / WWXRP
    // =====================================================================================

    function pm_placeBet(uint256 a, uint256 pSeed, bool over) external act(a) {
        _call(50, PARIMUTUEL, 0, abi.encodeWithSignature("placeBet(uint32,bool)", _id(pSeed), over));
    }

    function af_createCode(uint256 a, bytes32 code, uint8 kickback) external act(a) {
        _call(53, AFFILIATE, 0, abi.encodeWithSignature("createAffiliateCode(bytes32,uint8)", code, kickback));
    }

    function af_referPlayer(uint256 a, bytes32 code) external act(a) {
        _call(54, AFFILIATE, 0, abi.encodeWithSignature("referPlayer(bytes32)", code));
    }

    function af_claim(uint256 a, uint256[] calldata pSeeds) external act(a) {
        _call(55, AFFILIATE, 0, abi.encodeWithSignature("claim(address[])", _ps(pSeeds)));
    }

    function wx_enter(uint256 a, uint256 amount) external act(a) {
        _call(56, WWXRP_, 0, abi.encodeWithSignature("enter(uint32,uint256)", uint32(0), amount));
    }

    function wx_claim(uint256 a, uint24 day, uint32 entryIndex) external act(a) {
        _call(57, WWXRP_, 0, abi.encodeWithSignature("claim(uint24,uint32)", day, entryIndex));
    }

    // =====================================================================================
    // Craps (player doors on the deployed table; JackpotBattle doors route through its fallback)
    // =====================================================================================

    function cr_setPreferredBoard(uint256 a, uint32 chips) external act(a) {
        _call(58, CRAPS, 0, abi.encodeWithSignature("setPreferredBoard(uint32,uint32)", uint32(0), chips));
    }

    function cr_enterBattle(uint256 a, uint64 slot, uint32 chips, uint16 multiple) external act(a) {
        (bool okB, bytes memory retB) = _call(59, CRAPS, 0, abi.encodeWithSignature("enterBattle(uint32,uint64,uint32,uint16)", uint32(0), slot, chips, multiple));
        _recordBet(okB, retB);
    }

    function cr_enterBonusBattle(uint256 a, uint256 period, uint32 chips, uint16 multiple) external act(a) {
        (bool okB, bytes memory retB) = _call(60, CRAPS, 0, abi.encodeWithSignature("enterBonusBattle(uint32,uint256,uint32,uint16)", uint32(0), period, chips, multiple));
        _recordBet(okB, retB);
    }

    function cr_enterBonusDay(uint256 a, uint32 chips, uint16 multiple) external act(a) {
        _call(61, CRAPS, 0, abi.encodeWithSignature("enterBonusDay(uint32,uint32,uint16)", uint32(0), chips, multiple));
    }

    function cr_amendSlip(uint256 a, uint256 betId, uint32 chips) external act(a) {
        _call(62, CRAPS, 0, abi.encodeWithSignature("amendSlip(uint32,uint256,uint32)", uint32(0), betId, chips));
    }

    function cr_buyFutureCrapsDays(uint256 a, uint24 startDay, uint8 count, bool high, uint32 chips) external act(a) {
        _call(63, CRAPS, 0, abi.encodeWithSignature("buyFutureCrapsDays(uint32,uint24,uint8,bool,uint32)", uint32(0), startDay, count, high, chips));
    }

    function cr_applyCrapsPasses(uint256 a, uint24 startDay, uint8 count, bool high, uint32 chips) external act(a) {
        _call(64, CRAPS, 0, abi.encodeWithSignature("applyCrapsPasses(uint32,uint24,uint8,bool,uint32)", uint32(0), startDay, count, high, chips));
    }

    function cr_convertNormalToHigh(uint256 a, uint32 highCount) external act(a) {
        _call(65, CRAPS, 0, abi.encodeWithSignature("convertNormalToHigh(uint32,uint32)", uint32(0), highCount));
    }

    function cr_upgradeReservedDay(uint256 a, uint24 day) external act(a) {
        _call(66, CRAPS, 0, abi.encodeWithSignature("upgradeReservedDay(uint32,uint24)", uint32(0), day));
    }

    function cr_upgradeDayWindows(uint256 a, uint24 day, uint8 mask) external act(a) {
        _call(67, CRAPS, 0, abi.encodeWithSignature("upgradeDayWindows(uint32,uint24,uint8)", uint32(0), day, mask));
    }

    function cr_donate(uint256 a, bool custom, uint256 index, uint24 granules) external act(a) {
        _call(68, CRAPS, 0, abi.encodeWithSignature("donate(bool,uint256,uint24)", custom, index, granules));
    }

    function cr_createBattle(
        uint256 a,
        uint32 played,
        uint8 bankMult,
        uint16 goalMult,
        uint24 stakeUnits,
        uint40 closeTime,
        bool multiEntry,
        uint16 highRollerMult
    ) external act(a) {
        _call(69, CRAPS, 0, abi.encodeWithSignature(
            "createBattle(uint32,uint8,uint16,uint24,uint40,bool,uint16)",
            played, bankMult, goalMult, stakeUnits, closeTime, multiEntry, highRollerMult));
    }

    function cr_closeBattle(uint256 a, uint64 slot) external act(a) {
        _call(70, CRAPS, 0, abi.encodeWithSignature("closeBattle(uint64)", slot));
    }

    // =====================================================================================
    // AFKing seat token
    // =====================================================================================

    function st_transferFrom(uint256 a, uint256 fromSeed, uint256 toSeed, uint256 tokenId) external act(a) {
        _call(71, SEAT, 0, abi.encodeWithSignature("transferFrom(address,address,uint256)", _p(fromSeed), _p(toSeed), tokenId));
    }

    function st_safeTransferFrom(uint256 a, uint256 fromSeed, uint256 toSeed, uint256 tokenId) external act(a) {
        _call(72, SEAT, 0, abi.encodeWithSignature(
            "safeTransferFrom(address,address,uint256)", _p(fromSeed), _p(toSeed), tokenId));
    }

    function st_approve(uint256 a, uint256 toSeed, uint256 tokenId) external act(a) {
        _call(73, SEAT, 0, abi.encodeWithSignature("approve(address,uint256)", _p(toSeed), tokenId));
    }

    function st_setApprovalForAll(uint256 a, uint256 opSeed, bool approved) external act(a) {
        _call(74, SEAT, 0, abi.encodeWithSignature("setApprovalForAll(address,bool)", _p(opSeed), approved));
    }

    function st_setSeatTraits(uint256 a, uint256 tokenId, uint8 symbolId, uint24 bg, uint24 trim) external act(a) {
        _call(76, SEAT, 0, abi.encodeWithSignature("setSeatTraits(uint256,uint8,uint24,uint24)", tokenId, symbolId, bg, trim));
    }

    // =====================================================================================
    // Progress actions (bounded: they exist to move the game, not to probe inputs)
    // =====================================================================================

    function prog_buy(uint256 a, uint256 qty, uint256 lootboxAmt) external act(a) {
        _lastId = 77;
        ++calls[77];
        (,,,, uint256 priceWei) = game.purchaseInfo();
        qty = bound(qty, 400, 8000);
        lootboxAmt = bound(lootboxAmt, 0, 1 ether);
        if (lootboxAmt != 0 && lootboxAmt < 0.01 ether) lootboxAmt = 0.01 ether;
        uint256 cost = priceWei * qty / 400 + lootboxAmt;
        if (cost > currentActor.balance) return;
        vm.prank(currentActor);
        try game.purchase{value: cost}(
            0, qty, lootboxAmt == 0 ? 0 : BoxOrderLib.boCustomFloor(lootboxAmt), bytes32(0), MintPaymentKind.DirectEth, false
        ) {
            ++oks[77];
        } catch {}
    }

    function prog_bigBuy(uint256 a, uint256 eth) external act(a) {
        _lastId = 78;
        ++calls[78];
        (,,,, uint256 priceWei) = game.purchaseInfo();
        eth = bound(eth, 1 ether, 100 ether);
        if (eth > currentActor.balance || priceWei == 0) return;
        uint256 qty = eth * 400 / priceWei;
        vm.prank(currentActor);
        try game.purchase{value: eth}(0, qty, 0, bytes32(0), MintPaymentKind.DirectEth, false) {
            ++oks[78];
        } catch {}
    }

    function prog_mineFlip(uint256 a) external act(a) {
        _lastId = 79;
        ++calls[79];
        uint24 lvl = game.level();
        vm.prank(currentActor);
        try game.mineFlip() {
            ++oks[79];
            ++ghost_mines;
        } catch {}
        if (game.level() > lvl) ghost_levels += game.level() - lvl;
        if (game.gameOver()) ghost_gameOver = 1;
    }

    function prog_fulfillVrf(uint256 word) external {
        _lastId = 80;
        ++calls[80];
        if (_fulfill(word)) ++oks[80];
        _checkBystander(80);
    }

    function prog_warp(uint256 delta) external {
        _lastId = 81;
        ++calls[81];
        ++oks[81];
        vm.warp(block.timestamp + bound(delta, 1 minutes, 2 days));
        _checkBystander(81);
    }

    /// @notice Drive a whole day: warp into the next day, then alternate VRF fulfilment and mineFlip.
    function prog_driveDay(uint256 a, uint256 word) external act(a) {
        _lastId = 82;
        ++calls[82];
        uint24 lvl = game.level();
        vm.warp(block.timestamp + 1 days);
        bool any;
        for (uint256 i; i < 40; ++i) {
            _fulfill(uint256(keccak256(abi.encode(word, i))));
            vm.prank(currentActor);
            try game.mineFlip() {
                any = true;
                ++ghost_mines;
            } catch {
                if (!_fulfill(uint256(keccak256(abi.encode(word, i, "r"))))) break;
            }
        }
        if (any) ++oks[82];
        if (game.level() > lvl) ghost_levels += game.level() - lvl;
        if (game.gameOver()) ghost_gameOver = 1;
    }

    /// @notice Top an actor's FLIP / WWXRP back up so the burn-funded doors stay reachable.
    function prog_topUp(uint256 a) external act(a) {
        _lastId = 83;
        ++calls[83];
        ++oks[83];
        if (IAnyBalance(COIN).balanceOf(currentActor) < 100_000) {
            vm.prank(address(game));
            (bool ok,) = COIN.call(abi.encodeWithSignature("mintForGame(address,uint256)", currentActor, 1_000_000));
            ok;
        }
        if (IAnyBalance(WWXRP_).balanceOf(currentActor) < 1_000) {
            vm.prank(address(game));
            (bool ok,) = WWXRP_.call(abi.encodeWithSignature("mintPrize(address,uint256)", currentActor, 100_000));
            ok;
        }
    }


    // =====================================================================================
    // State-guided companions. The raw doors above stay the arbitrary-input probe; these derive the
    // arguments a real player would pass from the live state (own holdings, open windows, quotes),
    // so the same doors are also driven into their success paths and the state they build up
    // (bets, boons, sales, custom battles) is there for the raw doors to hit.
    // =====================================================================================

    uint256[] internal _betIds;
    address[] internal _betOwners;

    function _recordBet(bool ok, bytes memory ret) internal {
        if (ok && ret.length >= 32 && _betIds.length < 256) {
            _betIds.push(abi.decode(ret, (uint256)));
            _betOwners.push(currentActor);
        }
    }

    function _validChips(uint256 seed) internal pure returns (uint32) {
        if (seed % 4 == 0) return 0; // all random
        uint32 pass = uint32(seed % 4); // passLine 0..3
        uint32 six = uint32((seed >> 2) % 4); // place6 0..3
        uint32 eight = uint32((seed >> 4) % 2); // place8 0..1
        return pass | (six << 9) | (eight << 12);
    }

    function _crapsDay() internal view returns (uint24 day) {
        (bool ok, bytes memory r) = CRAPS.staticcall(abi.encodeWithSignature("currentBonusSlot()"));
        if (ok && r.length >= 96) (day,,) = abi.decode(r, (uint24, uint256, uint256));
    }

    function _multiple(uint256 seed) internal view returns (uint16) {
        if (seed % 3 != 0) return 1;
        (bool ok, bytes memory r) = CRAPS.staticcall(abi.encodeWithSignature("highMultForDay(uint24)", _crapsDay()));
        return ok && r.length >= 32 ? uint16(abi.decode(r, (uint256))) : 1;
    }

    function gd_sellFarFuture(uint256 a, uint256 lSeed, uint256 qSeed) external act(a) {
        uint24 active = game.level() + 1;
        for (uint256 off; off < 99; ++off) {
            uint24 lvl = active + 2 + uint24((lSeed % 99 + off) % 99);
            uint256 owned = game.entriesOwedView(lvl, currentActor);
            if (owned < 4) continue;
            uint24 key = lvl | uint24(1 << 22);
            uint256 len = TicketQueueStorage.length(address(game), key);
            for (uint256 j; j < len; ++j) {
                if (TicketQueueStorage.ownerAt(address(game), key, lvl, j) != currentActor) continue;
                uint32[] memory levels = new uint32[](1);
                uint256[] memory qtys = new uint256[](1);
                uint256[] memory idxs = new uint256[](1);
                levels[0] = lvl;
                qtys[0] = 4 * (1 + qSeed % (owned / 4));
                idxs[0] = j;
                _call(84, address(game), 0, abi.encodeWithSignature(
                    "sellFarFutureEntries(uint32,uint32[],uint256[],uint256[])", uint32(0), levels, qtys, idxs));
                return;
            }
        }
        _lastId = 84;
        ++calls[84];
    }

    function gd_issueDeityBoon(uint256 a, uint256 rSeed, uint8 slot) external act(a) {
        currentActor = actors[(a % 3) * 2 % actors.length]; // actors 0, 2, 4 hold deity passes
        _call(85, address(game), 0, abi.encodeWithSignature("issueDeityBoon(uint32,uint32,uint8)", uint32(0), _idNZ(rSeed), slot % 3));
    }

    function gd_placeDegenerette(uint256 a, uint256 pSeed, uint256 cSeed, uint256 aSeed, uint256 sSeed, uint256 symSeed)
        external
        act(a)
    {
        uint8 currency = uint8(cSeed % 2);
        uint128 amt;
        uint8 spins;
        uint256 value;
        if (currency == 0) {
            amt = uint128(0.005 ether * (1 + aSeed % 10));
            spins = uint8(1 + sSeed % 5);
            value = uint256(amt) * spins;
            if (value > currentActor.balance) value = 0;
        } else {
            amt = uint128(100 + aSeed % 5_000);
            spins = uint8(1 + sSeed % 15);
        }
        _call(86, address(game), value, abi.encodeWithSignature(
            "placeDegeneretteBet(uint32,uint8,uint128,uint8,uint8)", _id(pSeed), currency, amt, spins, uint8(symSeed % 24)));
    }

    function gd_enterBonusBattle(uint256 a, uint256 period, uint256 chipSeed, uint256 multSeed) external act(a) {
        (bool okB, bytes memory retB) = _call(87, CRAPS, 0, abi.encodeWithSignature(
            "enterBonusBattle(uint32,uint256,uint32,uint16)", uint32(0), period % 6, _validChips(chipSeed), _multiple(multSeed)));
        _recordBet(okB, retB);
    }

    function gd_enterBonusDay(uint256 a, uint256 chipSeed, uint256 multSeed) external act(a) {
        _call(88, CRAPS, 0, abi.encodeWithSignature(
            "enterBonusDay(uint32,uint32,uint16)", uint32(0), _validChips(chipSeed), _multiple(multSeed)));
    }

    function gd_createBattle(uint256 a, uint256 s) external act(a) {
        currentActor = actors[a % 3]; // actors 0..2 are battle creators
        _call(89, CRAPS, 0, abi.encodeWithSignature(
            "createBattle(uint32,uint8,uint16,uint24,uint40,bool,uint16)",
            uint32(300 + 300 * (s % 5)), uint8(1 + (s >> 8) % 25), uint16(5 + (s >> 16) % 20), uint24(2),
            uint40(block.timestamp + 2 hours), (s >> 24) % 2 == 1, uint16(0)));
    }

    function gd_enterBattle(uint256 a, uint256 chipSeed) external act(a) {
        (bool ok, bytes memory r) = CRAPS.staticcall(abi.encodeWithSignature("customBattleCount()"));
        uint64 n = ok && r.length >= 32 ? abi.decode(r, (uint64)) : 0;
        uint64 slot = (uint64(1) << 40) + (n == 0 ? 1 : n);
        (bool okB, bytes memory retB) = _call(90, CRAPS, 0, abi.encodeWithSignature("enterBattle(uint32,uint64,uint32,uint16)", uint32(0), slot, _validChips(chipSeed), uint16(1)));
        _recordBet(okB, retB);
    }

    function gd_amendSlip(uint256 a, uint256 pick, uint256 chipSeed) external act(a) {
        if (_betIds.length != 0) currentActor = _betOwners[pick % _betIds.length];
        uint256 betId = _betIds.length == 0 ? pick : _betIds[pick % _betIds.length];
        _call(91, CRAPS, 0, abi.encodeWithSignature("amendSlip(uint32,uint256,uint32)", uint32(0), betId, _validChips(chipSeed)));
    }

    function gd_reverseFlip(uint256 a) external act(a) {
        (, uint256 cost) = game.rngNudgeQuote();
        _call(92, address(game), 0, abi.encodeWithSignature("reverseFlip(uint256)", cost));
    }

    function gd_transferOwnSeat(uint256 a, uint256 toSeed) external act(a) {
        (bool ok, bytes memory r) = SEAT.staticcall(abi.encodeWithSignature("nextSerial()"));
        uint256 next = ok && r.length >= 32 ? abi.decode(r, (uint256)) : 0;
        uint256 id;
        for (uint256 i = 1; i < next; ++i) {
            (bool okO, bytes memory o) = SEAT.staticcall(abi.encodeWithSignature("ownerOf(uint256)", i));
            if (okO && o.length >= 32 && abi.decode(o, (address)) == currentActor) {
                id = i;
                break;
            }
        }
        _call(93, SEAT, 0, abi.encodeWithSignature("transferFrom(address,address,uint256)", currentActor, _p(toSeed), id));
    }

    function gd_claimFoilMatch(uint256 a, uint256 pSeed, uint256 dSeed, uint256 iSeed) external act(a) {
        uint256 day = uint256(game.currentDayView()) - (dSeed % 2);
        _call(94, address(game), 0, abi.encodeWithSignature("claimFoilMatch(uint32,uint256,uint256)", _id(pSeed), day, iSeed % 4));
    }


    function gd_smite(uint256 a, uint256 sSeed) external act(a) {
        uint256 k = a % 3;
        currentActor = actors[k * 2]; // deity holders: actor0 symbol 3, actor2 symbol 4, actor4 symbol 7
        uint256 symbol = k == 0 ? 3 : (k == 1 ? 4 : 7);
        _call(95, address(game), 0, abi.encodeWithSignature("smite(uint256,uint32)", symbol, _id(sSeed)));
    }

    function gd_sdgnrsBurn(uint256 a, uint256 amtSeed) external act(a) {
        uint256 bal = IAnyBalance(SDGNRS_).balanceOf(currentActor);
        uint256 span = bal / 1000 + 1;
        _call(96, SDGNRS_, 0, abi.encodeWithSignature("burn(uint256)", 1e18 + amtSeed % span));
    }

    function gd_burnWrapped(uint256 a, uint256 amtSeed) external act(a) {
        uint256 bal = IAnyBalance(DGNRS_).balanceOf(currentActor);
        uint256 span = bal / 1000 + 1;
        _call(97, SDGNRS_, 0, abi.encodeWithSignature("burnWrapped(uint256)", 1e18 + amtSeed % span));
    }

    function gd_referPlayer(uint256 a, uint256 oSeed) external act(a) {
        address other = actors[oSeed % actors.length];
        _call(98, AFFILIATE, 0, abi.encodeWithSignature("referPlayer(bytes32)", bytes32(uint256(uint160(other)))));
    }

    function gd_closeBattle(uint256 a) external act(a) {
        (bool ok, bytes memory r) = CRAPS.staticcall(abi.encodeWithSignature("customBattleCount()"));
        uint64 n = ok && r.length >= 32 ? abi.decode(r, (uint64)) : 0;
        _call(99, CRAPS, 0, abi.encodeWithSignature("closeBattle(uint64)", (uint64(1) << 40) + (n == 0 ? 1 : n)));
    }

    function gd_setOwnSeatTraits(uint256 a, uint8 sym, uint24 bg, uint24 trim) external act(a) {
        (bool ok, bytes memory r) = SEAT.staticcall(abi.encodeWithSignature("nextSerial()"));
        uint256 next = ok && r.length >= 32 ? abi.decode(r, (uint256)) : 0;
        uint256 id;
        for (uint256 i = 1; i < next; ++i) {
            (bool okO, bytes memory o) = SEAT.staticcall(abi.encodeWithSignature("ownerOf(uint256)", i));
            if (okO && o.length >= 32 && abi.decode(o, (address)) == currentActor) {
                id = i;
                break;
            }
        }
        _call(100, SEAT, 0, abi.encodeWithSignature("setSeatTraits(uint256,uint8,uint24,uint24)", id, sym % 32, bg, trim));
    }

    /// @notice Drive the next day from its first minute, so the period-0 craps window (the first 20
    ///         minutes of a day, the only time a day ticket can be bought) is live afterwards.
    function prog_driveDayAligned(uint256 a, uint256 word) external act(a) {
        _lastId = 101;
        ++calls[101];
        uint256 ts = block.timestamp;
        uint256 start = ts - ((ts - 82_620) % 1 days);
        vm.warp(start + 1 days + 60);
        uint24 lvl = game.level();
        bool any;
        for (uint256 i; i < 40; ++i) {
            _fulfill(uint256(keccak256(abi.encode(word, i, "aligned"))));
            vm.prank(currentActor);
            try game.mineFlip() {
                any = true;
                ++ghost_mines;
            } catch {
                if (!_fulfill(uint256(keccak256(abi.encode(word, i, "aligned-r"))))) break;
            }
        }
        if (any) ++oks[101];
        if (game.level() > lvl) ghost_levels += game.level() - lvl;
        if (game.gameOver()) ghost_gameOver = 1;
    }


    /// @notice Rarely (a quarter of the calls) let the VRF deadman fire: jump past 30 unprocessed
    ///         days, then crank, so the terminal path and every post-game-over door get exercised.
    function prog_deadman(uint256 a, uint256 gate) external act(a) {
        _lastId = 102;
        ++calls[102];
        if (gate % 4 != 0 || game.gameOver()) return;
        vm.warp(block.timestamp + 31 days);
        for (uint256 i; i < 80; ++i) {
            _fulfill(uint256(keccak256(abi.encode(gate, i, "deadman"))));
            vm.prank(currentActor);
            try game.mineFlip() {} catch {
                if (!_fulfill(uint256(keccak256(abi.encode(gate, i, "deadman-r"))))) break;
            }
        }
        if (game.gameOver()) {
            ++oks[102];
            ghost_gameOver = 1;
        }
    }


    function gd_buyPresaleBox(uint256 a, uint256 amtSeed) external act(a) {
        uint256 credit = game.presaleBoxCreditOf(currentActor);
        uint256 amount = credit > 0.01 ether ? 0.01 ether + amtSeed % (credit - 0.01 ether + 1) : 0.01 ether;
        uint256 value = amount <= currentActor.balance ? amount : 0;
        _call(103, address(game), value, abi.encodeWithSignature("buyPresaleBox(uint32,uint256)", uint32(0), amount));
    }

    function gd_buyLootboxAndPresaleBox(uint256 a, uint256 amtSeed) external act(a) {
        (,,,, uint256 priceWei) = game.purchaseInfo();
        uint256 credit = game.presaleBoxCreditOf(currentActor) + priceWei / 4;
        uint256 boxAmount = credit > 0.01 ether ? 0.01 ether + amtSeed % (credit - 0.01 ether + 1) : 0.01 ether;
        uint256 value = priceWei + boxAmount;
        if (value > currentActor.balance) value = 0;
        _call(104, address(game), value, abi.encodeWithSelector(
            DegenerusGame.buyLootboxAndPresaleBox.selector, uint32(0), uint256(400), uint256(0), bytes32(0),
            uint256(0), boxAmount));
    }

    function _fulfill(uint256 word) internal returns (bool) {
        uint256 reqId = vrf.lastRequestId();
        if (reqId == 0) return false;
        (,, bool fulfilled) = vrf.pendingRequests(reqId);
        if (fulfilled) return false;
        try vrf.fulfillRandomWords(reqId, word | 1) {
            ++ghost_vrf;
            return true;
        } catch {
            return false;
        }
    }

    // =====================================================================================
    // Reporting
    // =====================================================================================

    function actionName(uint256 id) external view returns (string memory) {
        return _names[id];
    }

    function revertSelectors(uint256 id) external view returns (bytes4[] memory) {
        return _revSels[id];
    }

    function _initNames() internal {
        string[N_ACTIONS] memory n = [
            string("cf_depositCoinflip"), "cf_claimCoinflips", "cf_claimCoinflipCarry", "cf_setCoinflipAutoRebuy",
            "cf_setCoinflipAutoRebuyTakeProfit", "g_purchase", "g_redeemFlip", "g_sellFarFutureEntries",
            "g_buyLootboxAndPresaleBox", "g_claimBingo", "g_claimDeadVrf", "g_claimFoilMatch",
            "g_claimFoilMatchMany", "g_claimGoldenTicket", "g_claimAffiliateDgnrs(addr)", "g_claimAffiliateDgnrs(addr[])",
            "g_claimWhalePass", "g_claimAfkingFlip", "g_withdrawAfkingFunding", "g_depositAfkingFunding",
            "g_reverseFlip", "g_issueDeityBoon", "g_subscribe", "g_setOperatorApproval",
            "g_placeDegeneretteBet", "g_claimWinnings", "g_claimWinnings(amount)", "g_decurse",
            "g_smite", "g_purchaseWhalePass", "g_purchaseLazyPass", "g_purchaseDeityPass",
            "g_buyPresaleBox", "g_claimWinningsStethFirst", "f_transfer", "f_transferFrom",
            "f_approve", "f_decimatorBurn", "d_transfer", "d_transferFrom",
            "d_approve", "d_burn", "s_burn", "s_burnWrapped",
            "s_claimRedemption", "s_claimParkedRedemption", "v_burnEth", "v_burnCoin",
            "gn_burn", "gn_vote", "pm_placeBet", "unused_51",
            "unused_52", "af_createAffiliateCode", "af_referPlayer", "af_claim",
            "wx_enter", "wx_claim", "cr_setPreferredBoard", "cr_enterBattle",
            "cr_enterBonusBattle", "cr_enterBonusDay", "cr_amendSlip", "cr_buyFutureCrapsDays",
            "cr_applyCrapsPasses", "cr_convertNormalToHigh", "cr_upgradeReservedDay", "cr_upgradeDayWindows",
            "cr_donate", "cr_createBattle", "cr_closeBattle", "st_transferFrom",
            "st_safeTransferFrom", "st_approve", "st_setApprovalForAll", "unused_75",
            "st_setSeatTraits", "prog_buy", "prog_bigBuy", "prog_mineFlip",
            "prog_fulfillVrf", "prog_warp", "prog_driveDay", "prog_topUp",
            "gd_sellFarFutureEntries", "gd_issueDeityBoon", "gd_placeDegeneretteBet", "gd_enterBonusBattle",
            "gd_enterBonusDay", "gd_createBattle", "gd_enterBattle", "gd_amendSlip",
            "gd_reverseFlip", "gd_transferOwnSeat", "gd_claimFoilMatch", "gd_smite",
            "gd_sdgnrsBurn", "gd_burnWrapped", "gd_referPlayer", "gd_closeBattle",
            "gd_setOwnSeatTraits", "prog_driveDayAligned", "prog_deadman", "gd_buyPresaleBox",
            "gd_buyLootboxAndPresaleBox"
        ];
        for (uint256 i; i < N_ACTIONS; ++i) _names[i] = n[i];
    }
}
