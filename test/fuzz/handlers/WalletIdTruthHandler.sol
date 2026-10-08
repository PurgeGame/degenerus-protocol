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
    function marketBetGates(uint32 player, uint24 lvl) external view returns (bool, bool, uint32);
}

interface IWidCraps {
    function betWordOf(uint256 betId) external view returns (uint256);
    function currentBonusSlot() external view returns (uint24 day, uint256 period, uint256 slot);
    function highMultForDay(uint24 day) external view returns (uint256);
}

interface IWidBalance {
    function balanceOf(address) external view returns (uint256);
}

interface IWidOwnerOf {
    function ownerOf(uint256) external view returns (address);
}

/// @title WalletIdTruthHandler -- every wallet-ID allocator, cache and account door on the real protocol
/// @notice Drives each door that allocates a Game wallet ID or fills a contract's ID cache, from a
///         seeded actor set plus fresh addresses minted on demand (so first contact happens on
///         every door), creates smurf accounts, and acts for accounts by wallet ID with random
///         callers (the account's payee, operators approved for it, the owner's operators and
///         strangers). It records every `WalletRegistered`, `SmurfCreated` and seat transfer.
///         `checkAll` is the suite-wide ID-truth oracle of LOOTBOX-ORDER-QUEUE-PLAN section 0,
///         extended to Phase F accounts:
///         - ordinary forward-registry entries agree with wallet-table addresses;
///         - account IDs are contiguous, allocated once, and stored IDs reference live accounts;
///         - subaccounts store only an ordinary owner ID, have their own mint flag and referral,
///           and emit one SmurfCreated event;
///         - at most one deity account belongs to a main wallet;
///         - authorized actions accept only owners or approved operators, except explicit gift
///           and permissionless credit doors; claims never allocate an account.
/// @dev Storage roots of the other contracts come from `scripts/layout/golden/<Contract>.json`;
///      the contract-specific ID suites and this suite's non-vacuity test pin them at runtime.
///      Two reachability shortcuts, both confined to one call: the Decimator window opens only at
///      levels x4/x99, so the burn doors open it for `level + 1` the way the advance does (window
///      flag and the round's `openedDay`) and shut the flag after the burn; the growth market opens
///      only in a jackpot phase at level >= 1, so the bet doors mock `growthState(0)` as open for
///      that one bet when the real market is shut. Neither touches an ID path.
///      The handler never pranks as a smurf key and never transfers anything to one: user
///      transfers to smurf keys are outside the invariant (PHASE-F-INVENTORY M14).
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
    address internal constant SEAT = ContractAddresses.AFKING_SUB_TOKEN;
    address internal constant DEITY_NFT = ContractAddresses.DEITY_PASS;
    address internal constant STETH = ContractAddresses.STETH_TOKEN;

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

    // ------------------------------------------------------------------ accounts (plan F1/F2, decisions G1/G4)
    uint256 internal constant SMURF_FLAG_SHIFT = 147; // mint word bit 147
    uint256 internal constant LANE_MASK = 0xffffffff; // wallet-table owner lane, bits 160..191

    bytes32 internal constant WALLET_REGISTERED = keccak256("WalletRegistered(uint32,address)");
    bytes32 internal constant SMURF_CREATED = keccak256("SmurfCreated(uint32,uint32)");
    bytes32 internal constant ERC721_TRANSFER = keccak256("Transfer(address,address,uint256)");
    bytes32 internal constant DEC_BURN_RECORDED =
        keccak256("DecBurnRecorded(uint32,uint24,uint64,uint256,uint256,uint256,uint32)");
    bytes32 internal constant DRAW_ENTERED =
        keccak256("DrawEntered(uint24,uint32,uint8,uint32,uint256,uint256,uint256)");
    bytes32 internal constant SLIP_PLACED = keccak256("CrapsSlipPlaced(uint32,uint256)");
    bytes4 internal constant NOT_APPROVED = bytes4(keccak256("NotApproved()"));
    bytes4 internal constant UNAUTHORIZED = bytes4(keccak256("Unauthorized()"));

    /// @dev Account-door flags: the class (bits 0..7: who may succeed for an allocated ID),
    ///      F_NP (a non-paying door: it must register nobody) and F_CR (an authorization error
    ///      for an authorized caller is a false reject).
    uint256 internal constant AUTH = 0; // authorized callers only (NotApproved)
    uint256 internal constant GIFT = 1; // anyone; an unauthorized caller funds a gift
    uint256 internal constant OPEN = 2; // permissionless
    uint256 internal constant SD_AUTH = 3; // authorized callers only (sDGNRS: Unauthorized)
    uint256 internal constant PAYEE_ONLY = 4; // the key or a smurf's owner (operator approvals)
    uint256 internal constant F_NP = 1 << 8;
    uint256 internal constant F_CR = 1 << 9;

    uint256 internal constant MAX_FRESH = 48;
    uint256 internal constant CAP = 512;

    // ------------------------------------------------------------------ actors and keys
    address[] public actors;
    address[] public keys;
    mapping(address => bool) public isKey;
    mapping(address => bool) internal _isProtocol;
    uint256 public freshCount;
    /// @dev operator => players that approved it for their own ID (Game approvals by ID 0)
    mapping(address => address[]) internal _approversOf;
    /// @dev account ID => operators approved for it through the handler (candidates; the
    ///      authorization oracle reads the approval from storage)
    mapping(uint32 => address[]) internal _opsOf;

    // ------------------------------------------------------------------ registration ghosts
    uint32[] public regIds;
    address[] public regOwners;
    uint256 public nonPayingRegs;
    string public nonPayingAction;

    // ------------------------------------------------------------------ smurf ghosts
    uint32[] public smurfIds;
    mapping(uint32 => uint256) public smurfCreatedCount;
    mapping(uint32 => uint32) public smurfCreatedOwner;
    uint256 public smurfReturnMismatch;
    mapping(uint32 => uint256) public lifetimeSmurfs;
    mapping(uint32 => uint16) public smurfBase;
    uint256 public quotaViolations;

    // ------------------------------------------------------------------ account-door ghosts
    uint256 public authViolations;
    string public authViolation;
    uint256 public authFalseRejects;
    string public authFalseReject;
    uint256 public unallocatedOks;
    string public unallocatedOk;
    uint256 public acctAuthorizedOks;
    uint256 public acctSmurfOks;
    uint256 public acctRejects;
    uint256 public acctGifts;

    // ------------------------------------------------------------------ seat ghosts
    uint256[] internal _seats;
    mapping(uint256 => address) internal _seatHolder;
    mapping(uint256 => bool) internal _seatKnown;

    // ------------------------------------------------------------------ stored-ID ghosts
    bytes32[] public codes;
    mapping(bytes32 => address) public codeCreator;

    struct WxEntry {
        uint24 day;
        uint8 bucket;
        uint32 index;
        uint32 entrant;
    }

    struct PmBet {
        uint24 round;
        uint8 side;
        uint32 index;
        uint32 bettor;
    }

    struct Slip {
        uint256 betId;
        uint32 playerId;
    }

    struct DecEntry {
        uint24 lvl;
        uint64 entryId;
        uint32 burner;
    }

    WxEntry[] internal _wx;
    PmBet[] internal _pm;
    uint24[] internal _pmRounds;
    mapping(uint24 => bool) internal _pmRoundSeen;
    Slip[] internal _slips;
    DecEntry[] internal _dec;

    // ------------------------------------------------------------------ coverage
    uint256 public constant N_ACTIONS = 74;
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
        address[14] memory protocol =
            [VAULT, SDGNRS, GNRUS, GAME, COINFLIP, COIN, CRAPS, AFFILIATE, WWXRP, DGNRS, PARIMUTUEL, QUESTS, JACKPOTS, ADMIN];
        for (uint256 i; i < protocol.length; ++i) {
            _isProtocol[protocol[i]] = true;
            if (i < 11) _addKey(protocol[i]);
        }
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

    /// @dev The account ID a door acts for when `player` is not the caller: its canonical ID,
    ///      or the next unallocated ID for a wallet without one (the door must then revert).
    function _idFor(address player, address caller) internal view returns (uint32) {
        if (player == caller) return 0;
        uint32 id = _fwd(player);
        return id != 0 ? id : uint32(_tableLength());
    }

    /// @dev An affiliate code: none, default codes of known wallets, smurf keys and brand-new
    ///      wallets, created custom codes, the protocol codes, and the rejected shapes (lock
    ///      sentinel, forged default word, unknown custom code).
    function _code(uint256 sel, address self) internal returns (bytes32) {
        uint256 k = sel % 10;
        if (k == 0) return bytes32(0);
        if (k == 2 && smurfIds.length != 0) return bytes32((uint256(1) << 160) | smurfIds[(sel >> 8) % smurfIds.length]);
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
                } else if (t0 == SMURF_CREATED && l.topics.length == 3) {
                    uint32 sid = uint32(uint256(l.topics[2]));
                    if (smurfCreatedCount[sid]++ == 0) smurfIds.push(sid);
                    uint32 mainId = uint32(uint256(l.topics[1]));
                    smurfCreatedOwner[sid] = mainId;
                    ++lifetimeSmurfs[mainId];
                } else if (t0 == keccak256("SmurfBaseAllowanceRaised(uint32,uint16,uint16)") && l.topics.length == 2) {
                    uint32 mainId = uint32(uint256(l.topics[1]));
                    (uint16 previous, uint16 next) = abi.decode(l.data, (uint16, uint16));
                    if (previous != smurfBase[mainId] || next <= previous) ++quotaViolations;
                    smurfBase[mainId] = next;
                } else if (t0 == DEC_BURN_RECORDED && l.topics.length == 4 && _dec.length < CAP) {
                    _dec.push(DecEntry(
                        uint24(uint256(l.topics[2])), uint64(uint256(l.topics[3])), uint32(uint256(l.topics[1]))
                    ));
                }
            } else if (l.emitter == SEAT && t0 == ERC721_TRANSFER && l.topics.length == 4) {
                uint256 t = uint256(l.topics[3]);
                if (!_seatKnown[t] && _seats.length < CAP) {
                    _seatKnown[t] = true;
                    _seats.push(t);
                }
                _seatHolder[t] = address(uint160(uint256(l.topics[2])));
            } else if (l.emitter == WWXRP && t0 == DRAW_ENTERED && l.topics.length == 3 && _wx.length < CAP) {
                (uint8 bucket, uint32 index,,,) = abi.decode(l.data, (uint8, uint32, uint256, uint256, uint256));
                _wx.push(WxEntry(uint24(uint256(l.topics[1])), bucket, index, uint32(uint256(l.topics[2]))));
            } else if (l.emitter == CRAPS && t0 == SLIP_PLACED && l.topics.length == 2 && _slips.length < CAP) {
                uint256 bet = abi.decode(l.data, (uint256));
                _slips.push(Slip((bet >> 32) & type(uint128).max, uint32(uint256(l.topics[1]))));
            }
        }
    }

    /// @dev A seat `holder` holds (0 when none is known), starting the scan at `s`.
    function _seatHeldBy(address holder, uint256 s) internal view returns (uint256) {
        uint256 n = _seats.length;
        if (n == 0) return 0;
        s %= n;
        for (uint256 i; i < n; ++i) {
            uint256 t = _seats[(s + i) % n];
            if (_seatHolder[t] == holder) return t;
        }
        return 0;
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
        uint32 id = oSeed % 4 == 0 ? _idFor(_approverOf(p, oSeed >> 2), p) : 0; // operator buys for its approver
        qty = bound(qty, 400, 4000);
        box = box % 3 == 0 ? 0 : bound(box, 0.01 ether, 0.3 ether);
        bytes memory data = _purchaseData(id, qty, box, _code(codeSel, p), kindSel % 5 == 0, kindSel % 11 == 0);
        _call(0, p, GAME, _price() * qty / 400 + box + (kindSel % 7 == 0 ? 0.003 ether : 0), data, false);
    }

    /// @dev `purchase(id, qty, box order, code, kind, foil)` calldata (ETH, or Combined).
    function _purchaseData(uint32 id, uint256 qty, uint256 boxAmt, bytes32 code, bool combined, bool foil)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(
            DegenerusGame.purchase.selector, id, qty, boxAmt == 0 ? 0 : BoxOrderLib.boCustomFloor(boxAmt), code,
            combined ? MintPaymentKind.Combined : MintPaymentKind.DirectEth, foil);
    }

    function g_boxOnly(uint256 a, uint256 amt, uint256 codeSel) external {
        address p = _actor(a);
        amt = bound(amt, 0.01 ether, 0.5 ether);
        _call(1, p, GAME, amt, _purchaseData(0, 0, amt, _code(codeSel, p), false, false), false);
    }

    function g_presaleBox(uint256 a, uint256 amtSeed) external {
        address p = _actor(a);
        uint256 credit = game.presaleBoxCreditOf(p);
        uint256 amount = credit > 0.01 ether ? 0.01 ether + amtSeed % (credit - 0.01 ether + 1) : 0.01 ether;
        _call(2, p, GAME, amount, abi.encodeWithSignature("buyPresaleBox(uint32,uint256)", uint32(0), amount), false);
    }

    function g_degenerette(uint256 a, uint256 oSeed, uint256 cSeed, uint256 aSeed, uint256 sSeed, uint256 sym)
        external
    {
        address p = _actor(a);
        uint32 id = oSeed % 3 == 0 ? _idFor(_other(oSeed >> 2), p) : 0; // a gift when the player is someone else
        (bytes memory data, uint256 value) = _degeneretteData(id, cSeed, aSeed, sSeed, sym);
        _call(3, p, GAME, value, data, false);
    }

    /// @dev A Degenerette bet for `id`: ETH (1..5 spins of 0.005..0.05 ETH) or FLIP (1..15 spins).
    function _degeneretteData(uint32 id, uint256 cSeed, uint256 aSeed, uint256 sSeed, uint256 sym)
        internal
        pure
        returns (bytes memory data, uint256 value)
    {
        uint8 currency = uint8(cSeed % 2);
        uint128 amt;
        uint8 spins;
        if (currency == 0) {
            amt = uint128(0.005 ether * (1 + aSeed % 10));
            spins = uint8(1 + sSeed % 5);
            value = uint256(amt) * spins;
        } else {
            amt = uint128(100 + aSeed % 5_000);
            spins = uint8(1 + sSeed % 15);
        }
        data = abi.encodeWithSignature(
            "placeDegeneretteBet(uint32,uint8,uint128,uint8,uint8)", id, currency, amt, spins, uint8(sym % 24));
    }

    function g_whalePass(uint256 a, uint256 codeSel, uint256 over) external {
        address p = _actor(a);
        uint256 value = game.level() <= 3 ? 2.4 ether : 4 ether;
        _call(4, p, GAME, value + (over % 5 == 0 ? 0.01 ether : 0), abi.encodeWithSignature(
            "purchaseWhalePass(uint32,uint256,bytes32)", uint32(0), uint256(1), _code(codeSel, p)), false);
    }

    function g_lazyPass(uint256 a, uint256 codeSel) external {
        address p = _actor(a);
        _call(5, p, GAME, 0.24 ether, abi.encodeWithSignature(
            "purchaseLazyPass(uint32,bytes32)", uint32(0), _code(codeSel, p)), false);
    }

    function g_deityPass(uint256 a, uint256 codeSel, uint256 symSeed) external {
        address p = _actor(a);
        uint256 price = _deityPrice();
        if (price == 0) return;
        _call(6, p, GAME, price, abi.encodeWithSignature(
            "purchaseDeityPass(uint32,uint8,bytes32)", uint32(0), uint8(symSeed % 32), _code(codeSel, p)), false);
    }

    /// @dev The next deity pass's price, or 0 once the handler stops selling them.
    function _deityPrice() internal view returns (uint256) {
        uint256 sold = uint8(uint256(vm.load(GAME, bytes32(GameSlots.DEITY_PASS_SALES))));
        if (sold > 12) return 0;
        return 24 ether + (sold * (sold + 1) * 1 ether) / 2;
    }

    function g_redeemFlip(uint256 a, uint256 qty) external {
        address p = _actor(a);
        _call(7, p, GAME, 0, abi.encodeWithSignature("redeemFlip(uint32,uint256)", uint32(0), 400 * (1 + qty % 4)), false);
    }

    /// @dev A self subscription burning a seat the caller holds (a new run needs one).
    function g_subscribe(uint256 a, uint256 v) external {
        address p = _actor(a);
        uint256 seat = _seatHeldBy(p, v);
        _call(8, p, GAME, bound(v, 0.01 ether, 1 ether), _subscribeData(0, false, 1, 0, seat), false);
    }

    /// @dev `subscribe(id, drain, tickets, qty, fundingSourceId, seatId)` calldata (ticket mode).
    function _subscribeData(uint32 id, bool drain, uint8 qty, uint32 src, uint256 seat)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSignature(
            "subscribe(uint32,bool,bool,uint8,uint32,uint256)", id, drain, true, qty, src, seat);
    }

    // =====================================================================================
    // Game doors (non-paying: the beneficiary must already hold an ID)
    // =====================================================================================

    function g_depositAfking(uint256 a, uint256 oSeed, uint256 v) external {
        address p = _actor(a);
        address beneficiary = oSeed % 2 == 0 ? p : _other(oSeed >> 1);
        // A third-party recipient by ID: an unregistered beneficiary passes 0, which reverts.
        _call(9, p, GAME, bound(v, 1, 1 ether), abi.encodeWithSignature(
            "depositAfkingFunding(uint32)", _fwd(beneficiary)), true);
    }

    function g_plainEth(uint256 a, uint256 v) external {
        address p = _actor(a);
        _call(10, p, GAME, bound(v, 1, 1 ether), "", true);
    }

    function g_claimWinnings(uint256 a) external {
        address p = _actor(a);
        _call(11, p, GAME, 0, abi.encodeWithSignature("claimWinnings(uint32)", uint32(0)), true);
    }

    function g_approve(uint256 a, uint256 oSeed) external {
        address p = _actor(a);
        address op = _other(oSeed);
        if (op == p) return;
        (bool ok,) = _call(12, p, GAME, 0, abi.encodeWithSignature(
            "setOperatorApproval(uint32,address,bool)", uint32(0), op, true), true);
        if (ok) {
            if (_approversOf[op].length < 16) _approversOf[op].push(p);
            uint32 id = _fwd(p);
            if (_opsOf[id].length < 16) _opsOf[id].push(op);
        }
    }

    // =====================================================================================
    // Coinflip
    // =====================================================================================

    /// @param mode 0 self, 1 operator (for a player that approved the caller), 2 gift
    function cf_deposit(uint256 a, uint256 mode, uint256 oSeed, uint256 amt) external {
        address p = _actor(a);
        uint32 id;
        uint256 m = mode % 3;
        if (m == 1) id = _idFor(_approverOf(p, oSeed), p);
        else if (m == 2) id = _idFor(_other(oSeed), p);
        _call(13, p, COINFLIP, 0, abi.encodeWithSignature("depositCoinflip(uint32,uint256)", id, bound(amt, 100, 50_000)), false);
    }

    function cf_claim(uint256 a, uint256 amt) external {
        address p = _actor(a);
        _call(14, p, COINFLIP, 0, abi.encodeWithSignature(
            "claimCoinflips(uint32,uint256)", uint32(0), amt % 2 == 0 ? type(uint256).max : amt % 100_000), true);
    }

    function cf_autoRebuy(uint256 a, bool enabled, uint256 takeProfit) external {
        address p = _actor(a);
        _call(15, p, COINFLIP, 0, abi.encodeWithSignature(
            "setCoinflipAutoRebuy(uint32,bool,uint256)", uint32(0), enabled, takeProfit % 1_000_000), false);
    }

    // =====================================================================================
    // FLIP decimator burn (window opened for this call only; see the contract notice)
    // =====================================================================================

    function f_decimatorBurn(uint256 a, uint256 amt, uint256 chipSeed) external {
        address p = _actor(a);
        bool forced = _openDecWindow();
        _call(16, p, COIN, 0, abi.encodeWithSignature(
            "decimatorBurn(uint32,uint256,uint32)", uint32(0), bound(amt, 2_000, 200_000), _validChips(chipSeed)), false);
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
        _call(17, _actor(a), CRAPS, 0, abi.encodeWithSignature(
            "setPreferredBoard(uint32,uint32)", uint32(0), _validChips(chipSeed)), true);
    }

    function cr_bonusBattle(uint256 a, uint256 period, uint256 chipSeed, uint256 multSeed) external {
        _call(18, _actor(a), CRAPS, 0, _bonusBattleData(0, period, chipSeed, multSeed), false);
    }

    function cr_bonusDay(uint256 a, uint256 chipSeed, uint256 multSeed) external {
        _call(19, _actor(a), CRAPS, 0, _bonusDayData(0, chipSeed, multSeed), false);
    }

    function cr_futureDays(uint256 a, uint256 off, uint256 count, bool high, uint256 chipSeed) external {
        _call(20, _actor(a), CRAPS, 0, _futureDaysData(0, off, count, high, chipSeed), false);
    }

    function cr_applyPasses(uint256 a, uint256 off, bool high, uint256 chipSeed) external {
        _call(21, _actor(a), CRAPS, 0, _applyPassesData(0, off, high, chipSeed), true);
    }

    function _bonusBattleData(uint32 id, uint256 period, uint256 chipSeed, uint256 multSeed)
        internal
        view
        returns (bytes memory)
    {
        return abi.encodeWithSignature(
            "enterBonusBattle(uint32,uint256,uint32,uint16)", id, period % 7, _validChips(chipSeed), _multiple(multSeed));
    }

    function _bonusDayData(uint32 id, uint256 chipSeed, uint256 multSeed) internal view returns (bytes memory) {
        return abi.encodeWithSignature("enterBonusDay(uint32,uint32,uint16)", id, _validChips(chipSeed), _multiple(multSeed));
    }

    function _futureDaysData(uint32 id, uint256 off, uint256 count, bool high, uint256 chipSeed)
        internal
        view
        returns (bytes memory)
    {
        uint24 day = _crapsDay() + 1 + uint24(off % 3);
        return abi.encodeWithSignature(
            "buyFutureCrapsDays(uint32,uint24,uint8,bool,uint32)", id, day, uint8(1 + count % 2), high, _validChips(chipSeed));
    }

    function _applyPassesData(uint32 id, uint256 off, bool high, uint256 chipSeed) internal view returns (bytes memory) {
        uint24 day = _crapsDay() + 1 + uint24(off % 3);
        return abi.encodeWithSignature(
            "applyCrapsPasses(uint32,uint24,uint8,bool,uint32)", id, day, uint8(1), high, _validChips(chipSeed));
    }

    /// @dev Amend an announced slip as its owner (a smurf's slip through its owner by ID), or a
    ///      random bet ID as anyone.
    function cr_amendSlip(uint256 a, uint256 pick, uint256 chipSeed) external {
        address p = _actor(a);
        uint32 id;
        uint256 betId = _slips.length == 0 ? pick : _slips[pick % _slips.length].betId;
        if (_slips.length != 0 && pick % 4 != 0) {
            uint32 owner = _slips[pick % _slips.length].playerId;
            if (owner != 0 && owner < _tableLength()) {
                uint256 el = _element(owner);
                p = _payeeOfElement(el);
                if ((el >> 160) & LANE_MASK != 0 || pick % 8 == 1) id = owner;
            }
        }
        if (_isProtocol[p]) p = actors[pick % actors.length];
        _call(22, p, CRAPS, 0, abi.encodeWithSignature(
            "amendSlip(uint32,uint256,uint32)", id, betId, _validChips(chipSeed)), true);
    }

    function cr_convert(uint256 a, uint256 n) external {
        _call(23, _actor(a), CRAPS, 0, abi.encodeWithSignature(
            "convertNormalToHigh(uint32,uint32)", uint32(0), uint32(1 + n % 2)), true);
    }

    function cr_upgradeReserved(uint256 a, uint256 off) external {
        _call(24, _actor(a), CRAPS, 0, abi.encodeWithSignature(
            "upgradeReservedDay(uint32,uint24)", uint32(0), _crapsDay() + 1 + uint24(off % 3)), true);
    }

    function cr_upgradeWindows(uint256 a, uint256 off, uint256 mask) external {
        _call(25, _actor(a), CRAPS, 0, abi.encodeWithSignature(
            "upgradeDayWindows(uint32,uint24,uint8)", uint32(0), _crapsDay() + uint24(off % 3), uint8(1 + mask % 63)),
            false);
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
        uint32[] memory subs = new uint32[](1);
        subs[0] = _fwd(sSeed % 2 == 0 ? p : actors[sSeed % actors.length]);
        _call(28, p, AFFILIATE, 0, abi.encodeWithSignature("claim(uint32[])", subs), true);
    }

    // =====================================================================================
    // WWXRP / Parimutuel / Admin
    // =====================================================================================

    function wx_enter(uint256 a, uint256 amt) external {
        _call(29, _actor(a), WWXRP, 0, abi.encodeWithSignature(
            "enter(uint32,uint256)", uint32(0), bound(amt, 25, 5_000)), false);
    }

    function wx_claim(uint256 a, uint256 daySel, uint256 idx) external {
        uint24 today = GameTimeLib.currentDayIndex();
        uint24 day = today > 2 ? today - 1 - uint24(daySel % 2) : 0;
        _call(30, _actor(a), WWXRP, 0, abi.encodeWithSignature("claim(uint24,uint32)", day, uint32(idx % 8)), true);
    }

    function pm_placeBet(uint256 a, uint256 oSeed, bool over) external {
        address p = _actor(a);
        address player = oSeed % 4 == 0 ? _approverOf(p, oSeed >> 2) : p;
        _pmBet(31, p, _idFor(player, p), player, over);
    }

    /// @dev One growth bet for account `id` (0 = the caller), recorded against `bettor`'s key.
    function _pmBet(uint256 action, address caller, uint32 id, address bettor, bool over) internal {
        (uint24 round, bool mocked) = _openGrowthMarket();
        if (round == 0) return;
        uint256 counts = uint256(vm.load(PARIMUTUEL, keccak256(abi.encode(uint256(round), PM_COUNTS))));
        uint32 index = uint32(over ? uint128(counts) : counts >> 128);
        bool ok = _pmCall(action, caller, id, over);
        if (mocked) vm.clearMockedCalls();
        if (ok) _notePmBet(round, over ? 1 : 2, index, id == 0 ? _fwd(caller) : id);
    }

    /// @dev The open round, mocking `growthState(0)` open for this bet when the market is shut
    ///      (round 0 after game over: no bet).
    function _openGrowthMarket() internal returns (uint24 round, bool mocked) {
        bool open;
        (,,, round, open,) = game.growthState(0);
        if (open && round != 0) return (round, false);
        if (game.gameOver()) return (0, false);
        round = round == 0 ? 1 : round;
        vm.mockCall(GAME, abi.encodeWithSignature("growthState(uint24)", uint24(0)),
            abi.encode(uint256(0), uint256(0), uint256(0), round, true, uint8(0)));
        mocked = true;
    }

    function _pmCall(uint256 action, address caller, uint32 id, bool over) internal returns (bool ok) {
        bytes memory data = abi.encodeWithSignature("placeBet(uint32,bool)", id, over);
        if (action == 31) (ok,) = _call(action, caller, PARIMUTUEL, 0, data, false);
        else ok = _acctCall(action, caller, id, PARIMUTUEL, 0, data, AUTH | F_CR);
    }

    function _notePmBet(uint24 round, uint8 side, uint32 index, uint32 bettor) internal {
        if (_pm.length >= CAP) return;
        _pm.push(PmBet(round, side, index, bettor));
        if (!_pmRoundSeen[round]) {
            _pmRoundSeen[round] = true;
            _pmRounds.push(round);
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
        (bool ok,) = _call(33, p, SDGNRS, 0, abi.encodeWithSignature("burn(uint256)", 1e12 + amtSeed % (bal / 1000 + 1)), true);
        _noteBurn(ok, p, batch);
    }

    function s_burnWrapped(uint256 a, uint256 amtSeed) external {
        address p = _actor(a);
        uint256 bal = IWidBalance(DGNRS).balanceOf(p);
        uint32 batch = _openBatch();
        (bool ok,) = _call(34, p, SDGNRS, 0, abi.encodeWithSignature("burnWrapped(uint256)", 1e12 + amtSeed % (bal / 1000 + 1)), true);
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
        _call(35, p, SDGNRS, 0, abi.encodeWithSignature("claimRedemption(uint32,uint32)", uint32(0), batch), true);
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
        _call(36, keeper, GAME, 0, abi.encodeWithSignature("mineFlip(uint32)", uint32(0)), false);
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
            (bool ok,) = _call(39, keeper, GAME, 0, abi.encodeWithSignature("mineFlip(uint32)", uint32(0)), false);
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
            (bool ok,) = _call(42, keeper, GAME, 0, abi.encodeWithSignature("mineFlip(uint32)", uint32(0)), false);
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
            DegenerusGame.purchase.selector, uint32(0), eth * 400 / priceWei, uint256(0), bytes32(0),
            MintPaymentKind.DirectEth, false), false);
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
    // Smurf accounts (plan F2, decision G7)
    // =====================================================================================

    /// @notice Create a smurf for a random owner (usually a registered actor, sometimes a wallet
    ///         with no ID, which must revert) with a blank, valid or unregistered default code.
    function sm_create(uint256 a, uint256 codeSel, uint256 kindSel) external {
        address p = _smurfOwner(a);
        _createSmurf(p, _smurfCode(codeSel, p), kindSel);
    }

    /// @notice Deterministic creation for the suite's tests. Not a fuzz target.
    function createSmurfFor(address owner, bytes32 code, uint256 kindSel) external returns (bool ok, uint32 smurfId) {
        return _createSmurf(owner, code, kindSel);
    }

    function _smurfOwner(uint256 a) internal returns (address) {
        if (a % 8 == 0) return _actor(a >> 3);
        for (uint256 i; i < 4; ++i) {
            address p = actors[(a >> (3 + 16 * i)) % actors.length];
            if (_fwd(p) != 0) return p;
        }
        return actors[0];
    }

    function _smurfCode(uint256 sel, address p) internal returns (bytes32) {
        uint256 k = sel % 6;
        if (k == 0) return bytes32(0);
        if (k == 1) return bytes32(uint256(uint160(actors[(sel >> 8) % actors.length])));
        if (k == 2 && codes.length != 0) return codes[(sel >> 8) % codes.length];
        if (k == 3 && freshCount < MAX_FRESH) return bytes32(uint256(uint160(_fresh()))); // unregistered owner
        if (k == 4) return bytes32("VAULT");
        return _code(sel >> 8, p);
    }

    /// @dev One `createSmurf` by `p`: ETH for the ticket (sometimes over), part ETH part credit,
    ///      or credit only.
    function _createSmurf(address p, bytes32 code, uint256 kindSel) internal returns (bool ok, uint32 smurfId) {
        (uint256 value, bytes memory data) = _smurfData(code, kindSel);
        uint256 before = smurfIds.length;
        uint32 mainId = game.walletIdOf(p);
        uint256 limit = uint256(smurfBase[mainId]) + game.playerActivityScoreById(mainId) / 120;
        if (limit > 65_535) limit = 65_535;
        uint256 created = lifetimeSmurfs[mainId];
        bytes memory ret;
        (ok, ret) = _call(43, p, GAME, value, data, false);
        if (ok) {
            if (created >= limit) ++quotaViolations;
            smurfId = abi.decode(ret, (uint32));
            if (smurfIds.length != before + 1 || smurfIds[before] != smurfId) ++smurfReturnMismatch;
        }
    }

    function _smurfData(bytes32 code, uint256 kindSel) internal view returns (uint256 value, bytes memory data) {
        uint256 price = _price();
        uint256 k = kindSel % 8;
        MintPaymentKind kind =
            k < 5 ? MintPaymentKind.DirectEth : (k < 7 ? MintPaymentKind.Combined : MintPaymentKind.Claimable);
        value = k < 5 ? price + (k == 4 ? 0.002 ether : 0) : (k < 7 ? price / 2 : 0);
        data = abi.encodeWithSignature("createSmurf(bytes32,uint8)", code, uint8(kind));
    }

    // =====================================================================================
    // Account doors: act for a random account ID with a random caller (plan F1, decision G1)
    // =====================================================================================

    function ac_game(uint256 door, uint256 idSel, uint256 cSel, uint256 p1, uint256 p2) external {
        uint32 id = _acctId(idSel);
        _acct(44 + door % 10, id, _acctCaller(id, cSel), p1, p2);
    }

    function ac_coinflip(uint256 door, uint256 idSel, uint256 cSel, uint256 p1, uint256 p2) external {
        uint32 id = _acctId(idSel);
        _acct(54 + door % 5, id, _acctCaller(id, cSel), p1, p2);
    }

    function ac_ext(uint256 door, uint256 idSel, uint256 cSel, uint256 p1, uint256 p2) external {
        uint32 id = _acctId(idSel);
        _acct(59 + door % 6, id, _acctCaller(id, cSel), p1, p2);
    }

    function ac_craps(uint256 door, uint256 idSel, uint256 cSel, uint256 p1, uint256 p2) external {
        uint32 id = _acctId(idSel);
        _acct(65 + door % 9, id, _acctCaller(id, cSel), p1, p2);
    }

    /// @notice One account door (actions 44..73) for account `id` by `caller`. Not a fuzz target.
    function actAs(uint256 action, uint32 id, address caller, uint256 p1, uint256 p2) external {
        require(id != 0 && action >= 44 && action < N_ACTIONS, "actAs: account door and nonzero ID");
        _acct(action, id, caller, p1, p2);
    }

    /// @notice `setOperatorApproval(id, op, approved)` by `caller`. Not a fuzz target.
    function approveFor(uint32 id, address caller, address op, bool approved) external returns (bool ok) {
        ok = _acctCall(50, caller, id, GAME, 0, abi.encodeWithSignature(
            "setOperatorApproval(uint32,address,bool)", id, op, approved), PAYEE_ONLY | F_NP | F_CR);
        if (ok && approved && _opsOf[id].length < 16) _opsOf[id].push(op);
    }

    /// @dev An account to act for: a smurf, an actor's ID, a protocol account, or an
    ///      unallocated ID.
    function _acctId(uint256 s) internal view returns (uint32 id) {
        uint256 k = s % 16;
        uint256 r = s >> 4;
        if (k < 7 && smurfIds.length != 0) return smurfIds[r % smurfIds.length];
        if (k < 14) {
            id = _fwd(actors[r % actors.length]);
            if (id != 0) return id;
        }
        if (k == 14) return uint32(1 + r % 3);
        return uint32(_tableLength() + r % 2);
    }

    /// @dev A caller for account `id`: its payee (the key, or a smurf's owner), an operator
    ///      approved for it, an operator of a smurf's owner (not authorized for the smurf), or a
    ///      third party. Protocol contracts never act.
    function _acctCaller(uint32 id, uint256 s) internal returns (address) {
        uint256 k = s % 8;
        uint256 r = s >> 3;
        if (id != 0 && id < _tableLength()) {
            uint256 el = _element(id);
            address payee = _payeeOfElement(el);
            if (k < 4 && !_isProtocol[payee]) return payee;
            if (k < 6 && _opsOf[id].length != 0) return _opsOf[id][r % _opsOf[id].length];
            uint32 ownerId = uint32((el >> 160) & LANE_MASK);
            if (k == 6 && ownerId != 0 && _opsOf[ownerId].length != 0) return _opsOf[ownerId][r % _opsOf[ownerId].length];
        }
        return _other(r);
    }

    function _acct(uint256 action, uint32 id, address caller, uint256 p1, uint256 p2) internal {
        if (action < 54) _acctGame(action, id, caller, p1, p2);
        else if (action < 59) _acctCoinflip(action, id, caller, p1, p2);
        else if (action < 65) _acctExt(action, id, caller, p1, p2);
        else _acctCraps(action, id, caller, p1, p2);
    }

    /// @dev One account-door call and its authorization bookkeeping. Expected authorization is
    ///      read from storage (plan F1): the caller is the key, the smurf key derives from the
    ///      caller and `id`, or `operatorApprovals[id][caller]` is set; `PAYEE_ONLY` doors take
    ///      only the key or the smurf's owner. A success for an unallocated ID, or by an
    ///      unauthorized caller on an AUTH door, is a violation; an authorized caller refused with
    ///      the door's authorization error is a false reject (with F_CR).
    function _acctCall(
        uint256 action,
        address caller,
        uint32 id,
        address target,
        uint256 value,
        bytes memory data,
        uint256 flags
    ) internal returns (bool ok) {
        uint256 st = _acctState(id, caller, flags & 0xff);
        bytes memory ret;
        (ok, ret) = _call(action, caller, target, value, data, flags & F_NP != 0);
        _acctBook(action, caller, id, flags, st, ok, ret);
    }

    /// @dev Bit 0: `id` allocated; bit 1: `caller` authorized for it; bit 2: it is a smurf.
    function _acctState(uint32 id, address caller, uint256 mode) internal view returns (uint256 st) {
        if (id == 0 || id >= _tableLength()) return 0;
        uint256 el = _element(id);
        bool auth = mode == PAYEE_ONLY ? caller == _payeeOfElement(el) : _authorized(id, caller);
        st = 1 | (auth ? 2 : 0) | ((el >> 160) & LANE_MASK != 0 ? 4 : 0);
    }

    function _acctBook(
        uint256 action,
        address caller,
        uint32 id,
        uint256 flags,
        uint256 st,
        bool ok,
        bytes memory ret
    ) internal {
        uint256 mode = flags & 0xff;
        if (ok) {
            if (st & 1 == 0) {
                if (unallocatedOks++ == 0) unallocatedOk = _acctNote(action, caller, id);
            } else if (st & 2 != 0) {
                ++acctAuthorizedOks;
                if (st & 4 != 0) ++acctSmurfOks;
            } else if (mode == GIFT) {
                ++acctGifts;
            } else if (mode != OPEN) {
                if (authViolations++ == 0) authViolation = _acctNote(action, caller, id);
            }
            return;
        }
        if (st & 1 == 0 || mode == GIFT || mode == OPEN) return;
        if (st & 2 == 0) {
            ++acctRejects;
            return;
        }
        bytes4 authErr = mode == SD_AUTH ? UNAUTHORIZED : NOT_APPROVED;
        if (flags & F_CR != 0 && ret.length >= 4 && bytes4(ret) == authErr) {
            if (authFalseRejects++ == 0) authFalseReject = _acctNote(action, caller, id);
        }
    }

    function _acctNote(uint256 action, address caller, uint32 id) internal view returns (string memory) {
        return string.concat(_names[action], " caller=", vm.toString(caller), " id=", vm.toString(uint256(id)));
    }

    function _authorized(uint32 id, address caller) internal view returns (bool) {
        return caller == _payeeOfElement(_element(id)) || _approved(id, caller);
    }

    function _approved(uint32 id, address op) internal view returns (bool) {
        bytes32 inner = keccak256(abi.encode(uint256(id), GameSlots.OPERATOR_APPROVALS));
        return uint256(vm.load(GAME, keccak256(abi.encode(op, inner)))) & 0xff != 0;
    }

    function _acctGame(uint256 action, uint32 id, address caller, uint256 p1, uint256 p2) internal {
        if (action == 44) {
            uint256 qty = 400 * (1 + p1 % 4);
            uint256 boxAmt = p2 % 3 == 0 ? 0 : bound(p2, 0.01 ether, 0.2 ether);
            bytes memory data = _purchaseData(id, qty, boxAmt, _code(p1 >> 8, caller), p1 % 5 == 4, p1 % 13 == 12);
            _acctCall(action, caller, id, GAME, _price() * qty / 400 + boxAmt, data, AUTH | F_CR);
        } else if (action == 45) {
            _acctCall(action, caller, id, GAME, 0, abi.encodeWithSignature(
                "redeemFlip(uint32,uint256)", id, 400 * (1 + p1 % 4)), AUTH | F_CR);
        } else if (action == 46) {
            bytes memory data = p1 % 2 == 0
                ? abi.encodeWithSignature("claimWinnings(uint32)", id)
                : abi.encodeWithSignature("claimWinnings(uint32,uint256)", id, 1 + p2 % 1 ether);
            _acctCall(action, caller, id, GAME, 0, data, AUTH | F_NP | F_CR);
        } else if (action == 47) {
            _acctCall(action, caller, id, GAME, 0, abi.encodeWithSignature(
                "withdrawAfkingFunding(uint32,uint256)", id, 1 + p1 % 0.5 ether), AUTH | F_NP | F_CR);
        } else if (action == 48) {
            _acctDegenerette(id, caller, p1, p2);
        } else if (action == 49) {
            _acctSubscribe(id, caller, p1, p2);
        } else if (action == 50) {
            address op = _other(p1);
            bool approved = p2 % 5 != 0;
            bool ok = _acctCall(action, caller, id, GAME, 0, abi.encodeWithSignature(
                "setOperatorApproval(uint32,address,bool)", id, op, approved), PAYEE_ONLY | F_NP | F_CR);
            if (ok && approved && _opsOf[id].length < 16) _opsOf[id].push(op);
        } else if (action == 51) {
            _acctPass(id, caller, p1, p2);
        } else if (action == 52) {
            _acctCall(action, caller, id, GAME, 0, abi.encodeWithSignature(
                "issueDeityBoon(uint32,uint32,uint8)", id, _acctId(p1), uint8(p2 % 3)), AUTH | F_NP | F_CR);
        } else {
            _acctCurse(id, caller, p1);
        }
    }

    function _acctDegenerette(uint32 id, address caller, uint256 p1, uint256 p2) internal {
        (bytes memory data, uint256 value) = _degeneretteData(id, p1, p1 >> 1, p2, p2 >> 8);
        _acctCall(48, caller, id, GAME, value, data, GIFT);
    }

    /// @dev Subscribe (or cancel) for the account, burning a seat its payee holds (or a wrong
    ///      one), self-funded, funded by the owner (same main wallet) or by a random account.
    function _acctSubscribe(uint32 id, address caller, uint256 p1, uint256 p2) internal {
        (uint32 src, uint256 seat, bool sameMain) = _subscribeTerms(id, p1, p2);
        uint8 qty = p1 % 6 == 0 ? 0 : uint8(1 + p1 % 3);
        bytes memory data = _subscribeData(id, p2 % 2 == 0, qty, src, seat);
        uint256 value = qty == 0 ? 0 : bound(p2 >> 64, 0.01 ether, 0.5 ether);
        _acctCall(49, caller, id, GAME, value, data, AUTH | (sameMain ? F_CR : 0));
    }

    /// @dev The funding source (self, the smurf's owner, or a random account), the seat (one
    ///      the payee holds, or any known seat) and whether the source shares the main wallet.
    function _subscribeTerms(uint32 id, uint256 p1, uint256 p2)
        internal
        view
        returns (uint32 src, uint256 seat, bool sameMain)
    {
        uint32 ownerId;
        if (id != 0 && id < _tableLength()) {
            uint256 el = _element(id);
            ownerId = uint32((el >> 160) & LANE_MASK);
            if (_seats.length != 0) {
                seat = p2 % 4 == 3 ? _seats[(p2 >> 2) % _seats.length] : _seatHeldBy(_payeeOfElement(el), p2 >> 2);
            }
        }
        uint256 fs = (p1 >> 8) % 6;
        if (fs == 4) src = ownerId;
        else if (fs == 5) src = _acctId(p1 >> 16);
        sameMain = src == 0 || src == id || src == ownerId;
    }

    /// @dev A whale, lazy or deity pass bought for the account.
    function _acctPass(uint32 id, address caller, uint256 p1, uint256 p2) internal {
        (uint256 value, bytes memory data) = _passData(id, p1, _code(p2, caller));
        if (data.length != 0) _acctCall(51, caller, id, GAME, value, data, AUTH | F_CR);
    }

    function _passData(uint32 id, uint256 p1, bytes32 code) internal view returns (uint256 value, bytes memory data) {
        uint256 kind = p1 % 3;
        if (kind == 0) {
            value = game.level() <= 3 ? 2.4 ether : 4 ether;
            data = abi.encodeWithSignature("purchaseWhalePass(uint32,uint256,bytes32)", id, uint256(1), code);
        } else if (kind == 1) {
            value = 0.24 ether;
            data = abi.encodeWithSignature("purchaseLazyPass(uint32,bytes32)", id, code);
        } else {
            value = _deityPrice();
            if (value != 0) {
                data = abi.encodeWithSignature("purchaseDeityPass(uint32,uint8,bytes32)", id, uint8((p1 >> 8) % 32), code);
            }
        }
    }

    /// @dev A paid cure of the account's curse, or a smite of it by a deity pass's holder (the
    ///      main wallet). Both are open to any caller; the caller pays.
    function _acctCurse(uint32 id, address caller, uint256 p1) internal {
        if (p1 % 2 == 0) {
            _acctCall(53, caller, id, GAME, 0, abi.encodeWithSignature("decurse(uint32)", id), OPEN);
            return;
        }
        uint256 sym = (p1 >> 1) % 32;
        try IWidOwnerOf(DEITY_NFT).ownerOf(sym) returns (address holder) {
            if (!_isProtocol[holder]) caller = holder;
        } catch {}
        _acctCall(53, caller, id, GAME, 0, abi.encodeWithSignature("smite(uint256,uint32)", sym, id), OPEN);
    }

    function _acctCoinflip(uint256 action, uint32 id, address caller, uint256 p1, uint256 p2) internal {
        uint256 amt = p1 % 2 == 0 ? type(uint256).max : p1 % 100_000;
        if (action == 54) {
            _acctCall(action, caller, id, COINFLIP, 0, abi.encodeWithSignature(
                "depositCoinflip(uint32,uint256)", id, bound(p1, 100, 50_000)), GIFT);
        } else if (action == 55) {
            _acctCall(action, caller, id, COINFLIP, 0, abi.encodeWithSignature(
                "claimCoinflips(uint32,uint256)", id, amt), AUTH | F_NP | F_CR);
        } else if (action == 56) {
            _acctCall(action, caller, id, COINFLIP, 0, abi.encodeWithSignature(
                "claimCoinflipCarry(uint32,uint256)", id, amt), AUTH | F_NP | F_CR);
        } else if (action == 57) {
            _acctCall(action, caller, id, COINFLIP, 0, abi.encodeWithSignature(
                "setCoinflipAutoRebuy(uint32,bool,uint256)", id, p2 % 2 == 0, p2 % 1_000_000), AUTH | F_NP | F_CR);
        } else {
            _acctCall(action, caller, id, COINFLIP, 0, abi.encodeWithSignature(
                "setCoinflipAutoRebuyTakeProfit(uint32,uint256)", id, p2 % 1_000_000), AUTH | F_NP | F_CR);
        }
    }

    function _acctExt(uint256 action, uint32 id, address caller, uint256 p1, uint256 p2) internal {
        if (action == 59) {
            bool forced = _openDecWindow();
            _acctCall(action, caller, id, COIN, 0, abi.encodeWithSignature(
                "decimatorBurn(uint32,uint256,uint32)", id, bound(p1, 2_000, 200_000), _validChips(p2)), AUTH | F_CR);
            if (forced) _shutDecWindow();
        } else if (action == 60) {
            address bettor = id != 0 && id < _tableLength() ? _keyOf(id) : address(0);
            _pmBet(action, caller, id, bettor, p1 % 2 == 0);
        } else if (action == 61) {
            _acctCall(action, caller, id, WWXRP, 0, abi.encodeWithSignature(
                "enter(uint32,uint256)", id, bound(p1, 25, 5_000)), AUTH | F_CR);
        } else if (action == 62) {
            uint256 top = ((uint256(game.level()) + 9) / 10) * 10;
            uint256 back = 10 * (p1 % 3);
            _acctCall(action, caller, id, JACKPOTS, 0, abi.encodeWithSignature(
                "claimBafConsolation(uint32,uint24)", id, uint24(top >= back ? top - back : top)), OPEN | F_NP);
        } else {
            uint32 open = _openBatch();
            uint32 batch = open > (p2 % 3) ? open - uint32(p2 % 3) : 0;
            string memory sig = action == 63 ? "claimRedemption(uint32,uint32)" : "claimParkedRedemption(uint32,uint32)";
            _acctCall(action, caller, id, SDGNRS, 0, abi.encodeWithSignature(sig, id, batch), SD_AUTH | F_NP | F_CR);
        }
    }

    function _acctCraps(uint256 action, uint32 id, address caller, uint256 p1, uint256 p2) internal {
        bytes memory data = _crapsData(action, id, p1, p2);
        bool paying = action == 66 || action == 67 || action == 68 || action == 73;
        _acctCall(action, caller, id, CRAPS, 0, data, AUTH | (paying ? 0 : F_NP) | F_CR);
    }

    function _crapsData(uint256 action, uint32 id, uint256 p1, uint256 p2) internal view returns (bytes memory) {
        if (action == 65) return abi.encodeWithSignature("setPreferredBoard(uint32,uint32)", id, _validChips(p2));
        if (action == 66) return _bonusBattleData(id, p1 >> 8, p2, p1 >> 16);
        if (action == 67) return _bonusDayData(id, p2, p1 >> 16);
        if (action == 68) return _futureDaysData(id, p1, p1 >> 8, p1 % 2 == 0, p2);
        if (action == 69) return _applyPassesData(id, p1, p1 % 2 == 0, p2);
        if (action == 70) return abi.encodeWithSignature("amendSlip(uint32,uint256,uint32)", id, _slipOf(id, p1), _validChips(p2));
        if (action == 71) return abi.encodeWithSignature("convertNormalToHigh(uint32,uint32)", id, uint32(1 + p1 % 2));
        uint24 day = _crapsDay() + 1 + uint24(p1 % 3);
        if (action == 72) return abi.encodeWithSignature("upgradeReservedDay(uint32,uint24)", id, day);
        return abi.encodeWithSignature("upgradeDayWindows(uint32,uint24,uint8)", id, day - 1, uint8(1 + (p1 >> 8) % 63));
    }

    /// @dev A slip the account owns when one was announced, else any announced slip.
    function _slipOf(uint32 id, uint256 s) internal view returns (uint256) {
        uint256 n = _slips.length;
        if (n == 0) return s;
        s %= n;
        for (uint256 i; i < n; ++i) {
            Slip storage sl = _slips[(s + i) % n];
            if (sl.playerId == id) return sl.betId;
        }
        return _slips[s % n].betId;
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

    /// @dev The payee of a wallet-table element: its key, or for a smurf its owner's key.
    function _payeeOfElement(uint256 el) internal view returns (address) {
        uint32 ownerId = uint32((el >> 160) & LANE_MASK);
        return ownerId == 0 ? address(uint160(el)) : _keyOf(ownerId);
    }




    function _mintWord(address key) internal view returns (uint256) {
        return uint256(vm.load(GAME, GameSlotKeys.mintPacked(key)));
    }

    function _fwd(address key) internal view returns (uint32) {
        return uint32(uint256(vm.load(GAME, GameSlotKeys.walletId(key))));
    }

    function _tableLength() internal view returns (uint256) {
        return uint256(vm.load(GAME, bytes32(GameSlots.WALLETS)));
    }

    /// @dev True when `id` is an allocated ID whose canonical pair agrees in both directions.
    function _registered(uint32 id) internal view returns (bool) {
        if (id == 0 || id >= _tableLength()) return false;
        uint256 el = _element(id);
        uint32 owner = uint32(el >> 160);
        return owner == 0 ? _fwd(address(uint160(el))) == id
            : address(uint160(el)) == address(0) && owner < id && uint32(_element(owner) >> 160) == 0;
    }

    function _referral(address k) internal view returns (uint256) { return _referralId(_fwd(k)); }

    function _referralId(uint32 id) internal view returns (uint256) {
        return uint256(vm.load(AFFILIATE, keccak256(abi.encode(id, AFF_REFERRAL))));
    }

    function _fail(string memory tag, string memory what, address key, uint256 a, uint256 b) internal pure {
        revert(string.concat(tag, ": ", what, " key=", vm.toString(key), " got=", vm.toString(a), " want=", vm.toString(b)));
    }

    /// @notice The suite-wide ID-truth invariant. Reverts with a tagged reason on the first breach.
    function checkAll() external view {
        _checkRegistry();
        _checkKeys();
        _checkSmurfs();
        _checkDeityGroup();
        _checkCodes();
        _checkEarnings();
        _checkWwxrp();
        _checkParimutuel();
        _checkCraps();
        _checkSdgnrsBatches();
        _checkDecimator();
        _checkBafBoard();
        _checkAccountDoors();
        if (nonPayingRegs != 0) {
            revert(string.concat("NONPAYING: a non-paying door registered a wallet: ", nonPayingAction));
        }
    }

    /// @dev Canonical pair, one registration per ID, contiguous IDs, protocol constants.
    function _checkRegistry() internal view {
        uint256 n = regIds.length;
        uint256 count = n + smurfIds.length;
        if (_tableLength() != count + 1) _fail("REGISTRY", "table length != all allocations + 1", address(0), _tableLength(), count + 1);
        if (_element(0) != 0 || _fwd(address(0)) != 0) revert("REGISTRY: zero identity assigned");
        if (n < 3 || regOwners[0] != VAULT || regOwners[1] != SDGNRS || regOwners[2] != GNRUS) revert("REGISTRY: protocol IDs changed");
        bool[] memory seen = new bool[](count + 1);
        for (uint256 i; i < n; ++i) {
            uint32 id = regIds[i]; address owner = regOwners[i];
            if (id == 0 || id > count || seen[id]) revert("REGISTRY: duplicate or invalid ordinary allocation");
            seen[id] = true;
            if (owner == address(0) || _keyOf(id) != owner || uint32(_element(id) >> 160) != 0) revert("REGISTRY: ordinary table mismatch");
            if (_fwd(owner) != id) _fail("REGISTRY", "forward registry disagrees with table", owner, _fwd(owner), id);
        }
        for (uint256 i; i < smurfIds.length; ++i) {
            uint32 id = smurfIds[i];
            if (id == 0 || id > count || seen[id]) revert("REGISTRY: duplicate or invalid subaccount allocation");
            seen[id] = true;
        }
        for (uint256 id = 1; id <= count; ++id) if (!seen[id]) revert("REGISTRY: allocation gap");
    }

    /// @dev Every ordinary wallet: canonical reverse direction and ID-keyed referral/quest state.
    function _checkKeys() internal view {
        uint256 len = _tableLength();
        for (uint256 i; i < keys.length; ++i) {
            address k = keys[i];
            uint32 id = _fwd(k);
            if (id != 0) {
                if (id >= len) _fail("KEYS", "forward ID past the table", k, id, len);
                if (_keyOf(id) != k) _fail("KEYS", "element at the forward ID does not hold the key", k, uint160(_keyOf(id)), uint160(k));
            } else if ((_mintWord(k) >> SMURF_FLAG_SHIFT) & 1 != 0) {
                _fail("SMURFFLAG", "smurf flag on an unregistered key", k, 1, 0);
            }
            _checkAccountRecords(k, id);
        }
    }

    function _checkAccountRecords(address k, uint32 id) internal view {
        uint256 w = _referralId(id);
        if (w > 1 && w < (uint256(1) << 192)) {
            if (w >> 32 != 1 || !_registered(uint32(w))) _fail("AFFILIATE", "invalid default referral ID word", k, w, id);
        }
        (bool mayBet,, uint32 gid) = IWidQuests(QUESTS).marketBetGates(id, 1);
        if (gid != id || (mayBet && id == 0)) _fail("QUESTS", "quest identity mismatch", k, gid, id);
    }

    /// @dev Every allocated element: owner lane, zero subaccount address, smurf flag, `SmurfCreated`,
    ///      and automatic main referral plus event-derived creation quotas.
    function _checkSmurfs() internal view {
        if (quotaViolations != 0) _fail("SMURFQUOTA", "invalid quota transition", address(0), quotaViolations, 0);
        uint256 len = _tableLength();
        for (uint32 id = 1; id < len; ++id) {
            uint256 mw = uint256(vm.load(GAME, GameSlotKeys.mintPacked(id)));
            if (uint16(mw >> 224) != lifetimeSmurfs[id]) _fail("SMURFQUOTA", "lifetime count differs from events", address(0), uint16(mw >> 224), lifetimeSmurfs[id]);
            if (uint16(mw >> 240) != smurfBase[id]) _fail("SMURFQUOTA", "base differs from grants", address(0), uint16(mw >> 240), smurfBase[id]);
            uint256 el = _element(id);
            if ((el >> 160) & LANE_MASK == 0) _checkOrdinary(id, address(uint160(el)));
            else _checkSmurf(id, el, len);
        }
        for (uint256 i; i < smurfIds.length; ++i) {
            if (smurfIds[i] >= len) _fail("SMURFEVENT", "SmurfCreated for an unallocated ID", address(0), smurfIds[i], len);
        }
    }

    function _checkOrdinary(uint32 id, address key) internal view {
        if ((_mintWord(key) >> SMURF_FLAG_SHIFT) & 1 != 0) _fail("SMURFFLAG", "smurf flag on an ordinary wallet", key, id, 0);
        if (smurfCreatedCount[id] != 0) _fail("SMURFEVENT", "SmurfCreated for an ordinary wallet", key, id, 0);
    }

    function _checkSmurf(uint32 id, uint256 el, uint256 len) internal view {
        address key = address(uint160(el));
        uint32 ownerId = uint32((el >> 160) & LANE_MASK);
        if (ownerId >= len) _fail("SMURFLANE", "owner lane past the table", key, ownerId, len);
        uint256 oel = _element(ownerId);
        if ((oel >> 160) & LANE_MASK != 0) _fail("SMURFLANE", "owner lane points at a smurf", key, ownerId, id);
        address ownerKey = address(uint160(oel));
        if (ownerKey == address(0)) _fail("SMURFLANE", "owner lane points at an empty element", key, ownerId, id);
        if (key != address(0)) _fail("SMURFLANE", "subaccount stores an address", key, uint160(key), 0);
        if ((uint256(vm.load(GAME, GameSlotKeys.mintPacked(id))) >> SMURF_FLAG_SHIFT) & 1 == 0) _fail("SMURFFLAG", "smurf mint word lost bit 147", key, id, 1);
        if (smurfCreatedCount[id] != 1) _fail("SMURFEVENT", "SmurfCreated count != 1", key, smurfCreatedCount[id], 1);
        if (smurfCreatedOwner[id] != ownerId) _fail("SMURFEVENT", "SmurfCreated owner != owner lane", key, smurfCreatedOwner[id], ownerId);
        _checkSmurfReferral(id, ownerId);
        _checkAccountRecords(address(0), id);
    }

    /// @dev Every child is permanently referred by its creation-time main ID.
    function _checkSmurfReferral(uint32 id, uint32 ownerId) internal view {
        uint256 sw = _referralId(id);
        uint256 expected = (uint256(1) << 32) | ownerId;
        if (sw != expected) _fail("SMURFREF", "subaccount referral differs from main ID", address(0), sw, expected);
    }

    /// @dev At most one deity per main wallet (decision G5): the deity accounts' payees differ.
    function _checkDeityGroup() internal view {
        uint256 n = uint256(vm.load(GAME, bytes32(GameSlots.DEITY_PASS_IDS)));
        if (n > 64) n = 64;
        uint256 base = uint256(keccak256(abi.encode(GameSlots.DEITY_PASS_IDS)));
        address[] memory mains = new address[](n);
        for (uint256 i; i < n; ++i) {
            uint32 did = uint32(uint256(vm.load(GAME, bytes32(base + (i >> 3)))) >> ((i & 7) << 5));
            if (did == 0 || did >= _tableLength()) _fail("DEITYGROUP", "deity ID not allocated", address(0), did, i);
            mains[i] = _payeeOfElement(_element(did));
            for (uint256 j; j < i; ++j) {
                if (mains[j] == mains[i]) _fail("DEITYGROUP", "two deities share a main wallet", mains[i], did, j);
            }
        }
    }

    /// @dev Account doors: no success for an unauthorized caller or an unallocated ID, no
    ///      authorization error for an authorized caller, and createSmurf's return is its event's ID.
    function _checkAccountDoors() internal view {
        if (authViolations != 0) revert(string.concat("AUTH: unauthorized caller succeeded: ", authViolation));
        if (unallocatedOks != 0) revert(string.concat("AUTH: unallocated account ID succeeded: ", unallocatedOk));
        if (authFalseRejects != 0) revert(string.concat("AUTHREJECT: authorized caller refused: ", authFalseReject));
        if (smurfReturnMismatch != 0) revert("SMURFEVENT: createSmurf returned an ID other than its SmurfCreated");
    }

    /// @dev The referrer ID a cache of `k`'s first hop must hold, from Game's canonical IDs.
    ///      `stable` is false for an unset referral, which must never be cached.
    function _canonRef(uint32 accountId) internal view returns (bool stable, uint32 id) {
        uint256 w = _referralId(accountId);
        if (w == 0) return (false, 1);
        if (w == 1) return (true, 1);
        if (w < (uint256(1) << 192)) return (true, uint32(w));
        bytes32 c = bytes32(w);
        if (c == bytes32("VAULT")) return (true, 1);
        if (c == bytes32("DGNRS")) return (true, 2);
        address creator = codeCreator[c];
        if (creator != address(0)) return (true, _fwd(creator));
        return (true, uint32(uint256(vm.load(AFFILIATE, keccak256(abi.encode(c, AFF_CODE))))));
    }

    /// @dev An upline cache pair (`cache` = valid bits 64/65 over upline1 [0:32) and upline2
    ///      [32:64)) for the owner whose key is `ownerKey`.
    function _checkUplines(string memory tag, uint32 ownerId, uint256 cache) internal view {
        address ownerKey = _payeeOfElement(_element(ownerId));
        uint32 u1 = uint32(cache);
        uint32 u2 = uint32(cache >> 32);
        if (cache & (uint256(1) << 64) != 0) {
            (bool stable, uint32 want) = _canonRef(ownerId);
            if (!stable) _fail(tag, "upline1 cached from an unset referral", ownerKey, u1, 0);
            if (u1 != want || !_registered(u1)) _fail(tag, "upline1 cache != canonical referrer", ownerKey, u1, want);
            if (cache & (uint256(1) << 65) != 0) {
                (bool stable2, uint32 want2) = _canonRef(u1);
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
        _checkUplines("AFFCODE", ownerId, cache);
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
                _checkUplines("AFFEARN", id, cache);
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
            if (id != e.entrant) _fail("WWXRP", "entry differs from emitted ID", address(0), id, e.entrant);
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
            if (id != b.bettor) _fail("PARIMUTUEL", "lane differs from selected ID", address(0), id, b.bettor);
        }
    }

    /// @dev Every slip the table announced: stored owner field and the announced ID agree and
    ///      are registered; bits above the compact header stay zero.
    function _checkCraps() internal view {
        for (uint256 i; i < _slips.length; ++i) {
            Slip memory s = _slips[i];
            if (!_registered(s.playerId)) _fail("CRAPSBET", "slip announced an unregistered ID", address(0), s.playerId, s.betId);
            uint256 w = IWidCraps(CRAPS).betWordOf(s.betId);
            if (w == 0) continue;
            if (uint32(w) != s.playerId) _fail("CRAPSBET", "stored bet owner != announced ID", _keyOf(s.playerId), uint32(w), s.playerId);
            if (w >> 73 != 0) _fail("CRAPSBET", "bet word reserved bits nonzero", _keyOf(s.playerId), w, 0);
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
                uint128 entry = uint128(uint256(vm.load(SDGNRS, bytes32(base + i / 2))) >> (128 * (i % 2)));
                if (entry == 0) continue; // settled or parked entries are cleared before recycling
                uint32 id = uint32(entry >> 80);
                if (!_registered(id)) _fail("SDGNRS", "queue recipient is unallocated", address(0), id, i);
            }
        }
    }

    /// @dev Compact Decimator entries: owner ID32, board30, stack66; two lanes per word.
    function _checkDecimator() internal view {
        for (uint256 i; i < _dec.length; ++i) {
            DecEntry memory e = _dec[i];
            uint256 p = uint256(e.entryId) - 1;
            uint256 key = (uint256(e.lvl) << 64) | (p >> 1);
            uint128 lane = uint128(uint256(vm.load(GAME, keccak256(abi.encode(key, GameSlots.DEC_BATTLE_ENTRIES)))) >> ((p & 1) * 128));
            uint256 w = lane;
            if (w == 0) continue;
            if (uint32(w) != e.burner || uint32(w) == 0) _fail("DECIMATOR", "entry differs from emitted ID", address(0), uint32(w), e.burner);
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
        return regIds.length + smurfIds.length;
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

    function smurfCount() external view returns (uint256) {
        return smurfIds.length;
    }

    function seatCount() external view returns (uint256) {
        return _seats.length;
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
        _names[43] = "sm_create";
        _names[44] = "ac_purchase";
        _names[45] = "ac_redeemFlip";
        _names[46] = "ac_claimWinnings";
        _names[47] = "ac_withdrawAfking";
        _names[48] = "ac_degenerette";
        _names[49] = "ac_subscribe";
        _names[50] = "ac_setApproval";
        _names[51] = "ac_pass";
        _names[52] = "ac_deityBoon";
        _names[53] = "ac_decurseSmite";
        _names[54] = "ac_cfDeposit";
        _names[55] = "ac_cfClaim";
        _names[56] = "ac_cfCarry";
        _names[57] = "ac_cfAutoRebuy";
        _names[58] = "ac_cfTakeProfit";
        _names[59] = "ac_decimatorBurn";
        _names[60] = "ac_pmBet";
        _names[61] = "ac_wxEnter";
        _names[62] = "ac_bafConsolation";
        _names[63] = "ac_sdClaim";
        _names[64] = "ac_sdClaimParked";
        _names[65] = "ac_crSetBoard";
        _names[66] = "ac_crBonusBattle";
        _names[67] = "ac_crBonusDay";
        _names[68] = "ac_crFutureDays";
        _names[69] = "ac_crApplyPasses";
        _names[70] = "ac_crAmendSlip";
        _names[71] = "ac_crConvert";
        _names[72] = "ac_crUpgradeReserved";
        _names[73] = "ac_crUpgradeWindows";
    }
}
