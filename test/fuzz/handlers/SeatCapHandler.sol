// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";
import {AFKingSubscriptionToken} from "../../../contracts/AFKingSubscriptionToken.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {DegenerusVault} from "../../../contracts/DegenerusVault.sol";
import {MockVRFCoordinator} from "../../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";
import {GameSlots, GameSlotKeys} from "../../helpers/GameSlots.sol";

/// @title SeatCapHandler — drives seats and subscriptions on a real deploy and keeps an
///        independent ghost model of every seat (owner per serial, balance per holder, live
///        count, burns) built from what each action is expected to do.
/// @dev Violations of an action's expected effect are counted here (the campaign runs with
///      fail_on_revert = false, so a handler revert would be ignored); the invariant asserts
///      none occurred. Free-tranche seats past the few the wallets buy are reached by writing
///      `freeClaims` and `nextSerial` in token slot 5 (compiled layout: renderer 0..19 |
///      nextSerial 20..23 | freeClaims 24..25 | liveSeats 26..27); the ghost records those
///      serials as minted and burned, the state of free seats whose runs have since left the set.
contract SeatCapHandler is Test {
    DegenerusGame internal immutable game;
    AFKingSubscriptionToken internal immutable token;
    DegenerusVault internal immutable vault;
    MockVRFCoordinator internal immutable vrf;
    address internal immutable sdgnrsAddr;

    address internal constant CREATOR = ContractAddresses.CREATOR;
    uint32 internal constant VAULT_ID = 1;
    uint32 internal constant SDGNRS_ID = 2;
    uint256 internal constant CAP = 2000;
    uint256 internal constant N_WALLETS = 10;
    uint256 internal constant MAX_SMURFS = 8;
    bytes4 internal constant NO_WORK = bytes4(keccak256("NoWork()"));
    bytes4 internal constant RNG_NOT_READY = bytes4(keccak256("RngNotReady()"));

    uint256 internal constant A_PASS = 0;
    uint256 internal constant A_SMURF = 1;
    uint256 internal constant A_APPROVE = 2;
    uint256 internal constant A_VMINT = 3;
    uint256 internal constant A_FFWD = 4;
    uint256 internal constant A_SUB = 5;
    uint256 internal constant A_UNDERFUND = 6;
    uint256 internal constant A_VAULTSUB = 7;
    uint256 internal constant A_XFER = 8;
    uint256 internal constant A_DAY = 9;
    uint256 internal constant A_MINE = 10;
    uint256 public constant N_ACTIONS = 11;

    address[] public wallets;
    address public immutable op;
    address public immutable vaultOp;
    address public immutable phantom;

    uint32[] public smurfIds;
    mapping(uint32 => address) public smurfOwner;
    mapping(uint32 => bool) public opApproved;

    // ── ghost seat model ──
    mapping(uint256 => address) public gOwner;
    mapping(address => uint256[]) internal seatsOf;
    mapping(uint256 => uint256) internal seatSlot; // index + 1 in seatsOf[gOwner[serial]]
    address[] public holders;
    mapping(address => bool) internal isHolder;
    uint256 public gLive;
    uint256 public gNext;
    uint256 public gBurns;
    uint256 public gFree;
    uint256 public gVaultMints;
    uint256 public gInsertions;
    bool public gVaultMinted;
    uint256[] public burnedSerials;
    uint256[] internal phantomLo;
    uint256[] internal phantomHi;

    uint256 public violations;
    string public firstViolation;
    uint256[N_ACTIONS] public calls;
    uint256[N_ACTIONS] public oks;
    mapping(uint256 => mapping(bytes4 => uint256)) public revCount;
    mapping(uint256 => bytes4[]) internal revSels;
    uint256 public dayCranks;
    uint256 public maxSum;
    uint256 public capHits;
    uint256 internal salt;

    constructor(DegenerusGame g, AFKingSubscriptionToken t, DegenerusVault v, MockVRFCoordinator r, address s) {
        game = g;
        token = t;
        vault = v;
        vrf = r;
        sdgnrsAddr = s;
        for (uint256 i; i < N_WALLETS; ++i) wallets.push(address(uint160(0x5EA70000 + i)));
        op = address(uint160(0x5EA7_0F00));
        vaultOp = address(uint160(0x5EA7_0F01));
        phantom = address(uint160(0x5EA7_0F02));
        gNext = 3;
        _gAdd(1, s);
        _gAdd(2, address(v));
        gLive = 2;
        _noteHolder(phantom);
        for (uint256 i; i < N_WALLETS; ++i) _noteHolder(wallets[i]);
    }

    // ═════════════════════════ ghost bookkeeping ═════════════════════════

    function _violate(string memory why) internal {
        if (violations == 0) firstViolation = why;
        ++violations;
    }

    function _noteRevert(uint256 action, bytes memory r) internal {
        bytes4 sel = r.length >= 4 ? bytes4(r) : bytes4(0);
        if (revCount[action][sel]++ == 0) revSels[action].push(sel);
    }

    function revertSelectors(uint256 action) external view returns (bytes4[] memory) {
        return revSels[action];
    }

    function _noteHolder(address h) internal {
        if (!isHolder[h]) {
            isHolder[h] = true;
            holders.push(h);
        }
    }

    function _gAdd(uint256 serial, address holder) internal {
        gOwner[serial] = holder;
        seatsOf[holder].push(serial);
        seatSlot[serial] = seatsOf[holder].length;
        _noteHolder(holder);
    }

    function _gRemove(uint256 serial) internal {
        address holder = gOwner[serial];
        uint256[] storage list = seatsOf[holder];
        uint256 at = seatSlot[serial] - 1;
        uint256 last = list[list.length - 1];
        list[at] = last;
        seatSlot[last] = at + 1;
        list.pop();
        delete seatSlot[serial];
        delete gOwner[serial];
    }

    function seatCount(address h) external view returns (uint256) {
        return seatsOf[h].length;
    }

    /// @dev Absorb serials minted since the last sync; `kind` 0 = no mint allowed, 1 = pass
    ///      purchase (free seats only), 2 = vault mint (vault seats only).
    function _syncMints(uint256 kind, uint256 free0) internal returns (uint256 minted) {
        uint256 n = token.nextSerial();
        if (n < gNext) {
            _violate("nextSerial went backwards");
            return 0;
        }
        for (uint256 s = gNext; s < n; ++s) {
            try token.ownerOf(s) returns (address o) {
                _gAdd(s, o);
                ++gLive;
            } catch {
                _violate("a minted serial is not live");
            }
        }
        minted = n - gNext;
        gNext = n;
        uint256 freeDelta = uint256(token.freeClaims()) - free0;
        if (kind == 2) {
            if (freeDelta != 0) _violate("a vault mint moved freeClaims");
            gVaultMints += minted;
            if (minted != 0) gVaultMinted = true;
        } else if (kind == 1) {
            if (freeDelta != minted) _violate("a pass mint that is not a free-tranche seat");
            if (minted != 0 && gVaultMinted) _violate("free mint after the first vault mint");
            gFree += minted;
        } else if (minted != 0) {
            _violate("seat minted outside a pass purchase or vault mint");
        }
    }

    function _checkLive() internal {
        if (token.totalSupply() != gLive) _violate("totalSupply != ghost live count");
        uint256 sum = token.totalSupply() + game.subscriberSetLength();
        if (sum > maxSum) maxSum = sum;
        if (sum >= CAP) ++capHits;
    }

    // ═════════════════════════ raw Game reads ═════════════════════════

    function _qty(uint32 id) internal view returns (uint256) {
        return id == 0 ? 0 : GameSlotKeys.subQuantity(address(game), id);
    }

    function _vaultPaused() internal view returns (bool) {
        uint256 packed = uint256(vm.load(address(game), bytes32(GameSlots.AFKING_PROTOCOL_FLAGS)));
        return uint8(packed >> (8 * GameSlots.AFKING_PROTOCOL_FLAGS_OFFSET)) & 4 != 0;
    }

    function _pos(uint32 id) internal view returns (uint256 position1) {
        if (id == 0) return 0;
        (, position1) = GameSlotKeys.subLane(address(game), id);
    }

    function _setElement(uint256 index) internal view returns (uint256) {
        return uint32(uint256(vm.load(address(game), bytes32(uint256(keccak256(abi.encode(GameSlots.SUBSCRIBERS))) + index / 3))) >> (85 * (index % 3)));
    }

    /// @dev Whether account `id` (key `key`) is in the set, cross-checking the element word.
    function _inSet(uint32 id, address) internal view returns (bool present, bool consistent) {
        uint256 p = _pos(id);
        if (p == 0) return (false, true);
        uint256 el = _setElement(p - 1);
        return (true, uint32(el) == id);
    }

    function exemptEntries() public view returns (uint256 e, bool sdgnrsIn, bool consistent) {
        (bool v, bool vc) = _inSet(VAULT_ID, address(vault));
        (bool s, bool sc) = _inSet(SDGNRS_ID, sdgnrsAddr);
        e = (v ? 1 : 0) + (s ? 1 : 0);
        sdgnrsIn = s;
        consistent = vc && sc;
    }

    // ═════════════════════════ actors ═════════════════════════

    struct Acct {
        uint32 id; // 0 = an unregistered wallet (self only)
        address key;
        address payee;
        address caller;
        uint32 callId;
    }

    /// @dev Pick an account and an authorized caller for it: a wallet itself, a smurf's owner,
    ///      or `op` where approved.
    function _pick(uint256 seed) internal view returns (Acct memory a) {
        // Bits 0..7 pick the account, 8..15 the operator route, bit 16 the self-call form.
        uint256 nS = smurfIds.length;
        uint256 i = (seed & 0xff) % (N_WALLETS + nS);
        bool viaOp = ((seed >> 8) & 0xff) % 3 == 0;
        if (i < N_WALLETS) {
            a.key = wallets[i];
            a.payee = a.key;
            a.id = game.walletIdOf(a.key);
            a.caller = a.key;
            a.callId = ((seed >> 16) & 1 == 0) ? 0 : a.id;
            if (viaOp && a.id != 0 && opApproved[a.id]) {
                a.caller = op;
                a.callId = a.id;
            }
        } else {
            a.id = smurfIds[i - N_WALLETS];
            a.key = address(0);
            a.payee = smurfOwner[a.id];
            a.caller = a.payee;
            a.callId = a.id;
            if (viaOp && opApproved[a.id]) a.caller = op;
        }
    }

    /// @dev Like `_pick`, but walks forward to an account with a live run when one exists.
    function _pickLive(uint256 seed) internal view returns (Acct memory a) {
        uint256 total = N_WALLETS + smurfIds.length;
        for (uint256 k; k < total; ++k) {
            uint256 sd = (seed & ~uint256(0xff)) | (((seed & 0xff) + k) % total);
            a = _pick(sd);
            if (_qty(a.id) != 0) return a;
        }
        a.id = 0;
    }

    /// @dev Like `_pick`, but walks forward to an account that is live or whose payee holds a seat.
    function _pickUseful(uint256 seed) internal view returns (Acct memory a) {
        uint256 total = N_WALLETS + smurfIds.length;
        for (uint256 k; k < total; ++k) {
            uint256 sd = (seed & ~uint256(0xff)) | (((seed & 0xff) + k) % total);
            a = _pick(sd);
            if (_qty(a.id) != 0 || seatsOf[a.payee].length != 0) return a;
        }
        a = _pick(seed);
    }

    function _fund(address who, uint256 amount) internal {
        vm.deal(who, who.balance + amount);
    }

    /// @dev A serial `payee` cannot burn: another holder's, a burned one, a never-minted one or 0.
    function _wrongSeat(address payee, uint256 seed) internal view returns (uint256) {
        uint256 k = seed % 4;
        if (k == 0 && holders.length != 0) {
            address h = holders[(seed >> 8) % holders.length];
            if (h != payee && seatsOf[h].length != 0) return seatsOf[h][(seed >> 16) % seatsOf[h].length];
        }
        if (k == 1 && burnedSerials.length != 0) return burnedSerials[(seed >> 8) % burnedSerials.length];
        if (k == 2) return gNext + 1 + (seed >> 8) % 50;
        return 0;
    }

    // ═════════════════════════ actions ═════════════════════════

    /// @notice A wallet (self) or a smurf (its owner paying) buys a pass; a free seat, if any,
    ///         must reach the payee.
    function passPurchase(uint256 seed) external {
        ++calls[A_PASS];
        Acct memory a = _pick(seed);
        uint32 callId = a.id == 0 ? 0 : (a.caller == a.key ? 0 : a.id);
        address caller = a.payee; // the wallet itself or the smurf's owner pays
        uint256 free0 = token.freeClaims();
        _fund(caller, 3 ether);
        bool ok;
        vm.prank(caller);
        try game.purchaseLazyPass{value: 0.24 ether}(callId, bytes32(0)) {
            ok = true;
        } catch {
            vm.prank(caller);
            try game.purchaseWhalePass{value: 2.4 ether}(callId, 1, bytes32(0)) {
                ok = true;
            } catch (bytes memory r) {
                _noteRevert(A_PASS, r);
            }
        }
        uint256 first = gNext;
        uint256 minted = _syncMints(1, free0);
        for (uint256 s = first; s < first + minted; ++s) {
            if (gOwner[s] != a.payee) _violate("free seat not minted to the payee");
        }
        if (ok) ++oks[A_PASS];
        _checkLive();
    }

    function createSmurf(uint256 seed) external {
        ++calls[A_SMURF];
        if (smurfIds.length >= MAX_SMURFS) return;
        address owner = wallets[seed % N_WALLETS];
        if (game.walletIdOf(owner) == 0) return;
        uint256 price = game.mintPrice();
        _fund(owner, price);
        vm.prank(owner);
        try game.createSmurf{value: price}(bytes32(0), MintPaymentKind.DirectEth) returns (uint32 sid) {
            smurfIds.push(sid);
            smurfOwner[sid] = owner;
            ++oks[A_SMURF];
        } catch (bytes memory r) {
            _noteRevert(A_SMURF, r);
        }
        _syncMints(0, token.freeClaims());
        _checkLive();
    }

    /// @notice A wallet approves (or revokes) `op` for its own ID or for one of its smurfs.
    function approveOperator(uint256 seed) external {
        ++calls[A_APPROVE];
        Acct memory a = _pick(seed);
        if (a.id == 0) return;
        bool approve = (seed >> 48) % 4 != 0;
        uint32 callId = a.key == a.payee ? 0 : a.id;
        vm.prank(a.payee);
        try game.setOperatorApproval(callId, op, approve) {
            opApproved[a.id] = approve;
            ++oks[A_APPROVE];
        } catch {
            _violate("an account's payee could not set an operator approval");
        }
    }

    /// @notice A vault-owner mint of `n` seats: refused exactly while the free tranche is open
    ///         or when live seats + n + set length would pass 2,000.
    function vaultMint(uint256 seed, uint256 nRaw) external {
        ++calls[A_VMINT];
        uint256 l = token.totalSupply();
        uint256 s = game.subscriberSetLength();
        uint256 free0 = token.freeClaims();
        uint256 room = l + s < CAP ? CAP - l - s : 0;
        uint256 n = seed % 5 == 0 ? room + (seed >> 8) % 3 : nRaw % 41;
        address to = _recipient(seed >> 16);
        bool expectRevert = n != 0 && (free0 < 1000 || l + n + s > CAP);
        vm.prank(CREATOR);
        try vault.afkingSeatMint(to, n) {
            if (expectRevert) _violate("vault mint past a gate succeeded");
            ++oks[A_VMINT];
        } catch (bytes memory r) {
            if (!expectRevert) _violate("vault mint within both gates refused");
            bytes4 want = free0 < 1000
                ? AFKingSubscriptionToken.FreeTrancheOpen.selector
                : AFKingSubscriptionToken.SeatCapReached.selector;
            if (bytes4(r) != want) _violate("vault mint refused with the wrong error");
        }
        _syncMints(2, free0);
        _checkLive();
    }

    /// @notice Jump the free tranche to (or near) its end, or fill vault seats up to the cap.
    function fastForward(uint256 seed) external {
        ++calls[A_FFWD];
        uint256 free0 = token.freeClaims();
        if (free0 < 1000) {
            uint256 leave = seed % 3;
            if (1000 - free0 <= leave) return;
            uint256 k = 1000 - free0 - leave;
            _jumpFreeTranche(k);
            ++oks[A_FFWD];
            return;
        }
        uint256 l = token.totalSupply();
        uint256 s = game.subscriberSetLength();
        uint256 h = (seed >> 8) % 2 == 0 ? 0 : seed % 4;
        if (l + s + h >= CAP) return;
        uint256 n = CAP - h - l - s;
        address to = (seed >> 16) % 2 == 0 ? phantom : wallets[(seed >> 24) % N_WALLETS];
        vm.prank(CREATOR);
        try vault.afkingSeatMint(to, n) {
            ++oks[A_FFWD];
        } catch {
            _violate("bulk vault mint within both gates refused");
        }
        _syncMints(2, free0);
        _checkLive();
    }

    /// @dev `k` free seats minted and since burned by runs that left the set: freeClaims and
    ///      nextSerial advance by `k`; live seats and balances do not.
    function _jumpFreeTranche(uint256 k) internal {
        bytes32 slot = bytes32(uint256(5));
        uint256 w = uint256(vm.load(address(token), slot));
        uint256 next = uint32(w >> 160);
        uint256 free = uint16(w >> 192);
        require(next == token.nextSerial() && free == token.freeClaims(), "token slot 5 layout");
        w = (w & ~(uint256(type(uint32).max) << 160)) | ((next + k) << 160);
        w = (w & ~(uint256(type(uint16).max) << 192)) | ((free + k) << 192);
        vm.store(address(token), slot, bytes32(w));
        require(token.nextSerial() == next + k && token.freeClaims() == free + k, "token slot 5 write");
        phantomLo.push(gNext);
        phantomHi.push(gNext + k);
        gNext += k;
        gBurns += k;
        gFree += k;
    }

    /// @notice New run, change or cancel of a wallet or smurf, by its key, its owner or an
    ///         approved operator.
    function subscribe(uint256 seed) external {
        ++calls[A_SUB];
        Acct memory a = (seed >> 56) % 5 == 0 ? _pick(seed) : _pickUseful(seed);
        bool live = _qty(a.id) != 0;
        uint256 mode = (seed >> 56) % 5;
        if (!live) {
            uint256 seat = (mode != 0 && seatsOf[a.payee].length != 0)
                ? seatsOf[a.payee][(seed >> 64) % seatsOf[a.payee].length]
                : _wrongSeat(a.payee, seed >> 72);
            _newRun(a, seat, seed);
        } else if (mode < 3) {
            uint256 seat = seatsOf[a.payee].length != 0
                ? seatsOf[a.payee][(seed >> 64) % seatsOf[a.payee].length]
                : 424242;
            _change(a, seat, uint8(1 + (seed >> 80) % 3));
        } else {
            _change(a, seatsOf[a.payee].length != 0 ? seatsOf[a.payee][0] : 77, 0);
        }
        _syncMints(0, token.freeClaims());
        _checkLive();
    }

    function _newRun(Acct memory a, uint256 seat, uint256 seed) internal {
        bool valid = seat != 0 && gOwner[seat] == a.payee;
        bool wasInSet = _pos(a.id) != 0;
        uint256 s0 = game.subscriberSetLength();
        uint256 l0 = token.totalSupply();
        uint256 fund = 0.02 ether + (seed >> 88) % 5 * 0.01 ether;
        _fund(a.caller, fund);
        vm.prank(a.caller);
        try game.subscribe{value: fund}(a.callId, (seed >> 96) & 1 == 1, 1, seat) {
            if (!valid) {
                _violate("a new run started without a payee seat");
                return;
            }
            ++oks[A_SUB];
            uint32 id = a.id == 0 ? game.walletIdOf(a.key) : a.id;
            try token.ownerOf(seat) returns (address) {
                _violate("the named seat survived a new run");
                return;
            } catch {}
            _gRemove(seat);
            --gLive;
            ++gBurns;
            burnedSerials.push(seat);
            if (token.totalSupply() != l0 - 1) _violate("a new run burned other than one seat");
            uint256 s1 = game.subscriberSetLength();
            if (!wasInSet) {
                if (s1 != s0 + 1) _violate("a new run outside the set did not add one entry");
                ++gInsertions;
            } else {
                _violate("a new run found its account already in the set");
            }
            if (_qty(id) == 0 || _pos(id) == 0) _violate("new run not live in the set");
        } catch (bytes memory r) {
            _noteRevert(A_SUB, r);
            if (valid && bytes4(r) == AFKingSubscriptionToken.InvalidToken.selector) {
                _violate("a payee-held seat was refused");
            }
            if (token.totalSupply() != l0 || game.subscriberSetLength() != s0) _violate("a refused subscribe moved state");
        }
    }

    /// @dev A change (`qty > 0`) or a cancel (`qty == 0`) of a live run: never burns. A cancel
    ///      removes the entry; a change keeps it.
    function _change(Acct memory a, uint256 seat, uint8 qty) internal {
        uint256 s0 = game.subscriberSetLength();
        uint256 l0 = token.totalSupply();
        address seatOwner = gOwner[seat];
        uint256 fund = qty == 0 ? 0 : 0.01 ether;
        _fund(a.caller, fund);
        vm.prank(a.caller);
        try game.subscribe{value: fund}(a.callId, false, qty, seat) {
            ++oks[A_SUB];
            if (token.totalSupply() != l0) _violate("a change or cancel burned a seat");
            if (seatOwner != address(0)) {
                try token.ownerOf(seat) returns (address o) {
                    if (o != seatOwner) _violate("a change or cancel moved the named seat");
                } catch {
                    _violate("a change or cancel burned the named seat");
                }
            }
            if (game.subscriberSetLength() != (qty == 0 ? s0 - 1 : s0)) {
                _violate("a change kept, or a cancel removed, other than its own entry");
            }
            if (_qty(a.id) != qty) _violate("dailyQuantity not written");
        } catch (bytes memory r) {
            _noteRevert(A_SUB, r);
        }
    }

    /// @notice Strip a live account's funding so the next process pass evicts it.
    function underfund(uint256 seed) external {
        ++calls[A_UNDERFUND];
        Acct memory a = _pickLive(seed);
        if (a.id == 0) return;
        uint256 balances = uint256(vm.load(address(game), GameSlotKeys.balances(a.id)));
        uint256 rem = balances >> 128;
        if (rem != 0) {
            vm.prank(a.caller);
            try game.withdrawAfkingFunding(a.id, rem) {
                ++oks[A_UNDERFUND];
            } catch (bytes memory r) {
                _noteRevert(A_UNDERFUND, r);
            }
        }
        if (uint128(balances) > 1) {
            vm.prank(a.caller);
            try game.claimWinnings(a.id) {} catch {}
        }
        _syncMints(0, token.freeClaims());
        _checkLive();
    }

    /// @notice The vault-approved operator changes, pauses or resumes the permanent VAULT entry.
    ///         Naming a seat never burns it; pausing never releases the counted entry.
    function vaultSubscription(uint256 seed) external {
        ++calls[A_VAULTSUB];
        bool live = !_vaultPaused();
        uint256 position = _pos(VAULT_ID);
        uint256 s0 = game.subscriberSetLength();
        uint256 l0 = token.totalSupply();
        address owner2 = gOwner[2];
        uint256 seat = (seed >> 8) % 2 == 0 ? 2 : 1 + (seed >> 16) % (gNext + 5);
        uint8 qty = live ? ((seed % 3 == 0) ? 0 : uint8(1 + (seed >> 24) % 3)) : 1;
        vm.prank(vaultOp);
        try game.subscribe(VAULT_ID, false, qty, seat) {
            ++oks[A_VAULTSUB];
            if (token.totalSupply() != l0) _violate("an exempt subscription burned a seat");
            if (owner2 != address(0)) {
                try token.ownerOf(2) returns (address o) {
                    if (o != owner2) _violate("serial 2 moved");
                } catch {
                    _violate("serial 2 burned by an exempt subscription");
                }
            }
            if (game.subscriberSetLength() != s0 || _pos(VAULT_ID) != position) {
                _violate("a VAULT change, pause or resume moved its set entry");
            }
            if (qty == 0 ? !_vaultPaused() : (_vaultPaused() || _qty(VAULT_ID) != qty)) {
                _violate("VAULT quantity or pause was not updated");
            }
        } catch (bytes memory r) {
            _noteRevert(A_VAULTSUB, r);
        }
        _syncMints(0, token.freeClaims());
        _checkLive();
    }

    function _recipient(uint256 seed) internal view returns (address) {
        uint256 k = seed % 5;
        if (k == 0) return phantom;
        if (k == 1 && smurfIds.length != 0) return smurfOwner[smurfIds[(seed >> 8) % smurfIds.length]];
        if (k == 2) return address(vault);
        return wallets[(seed >> 8) % N_WALLETS];
    }

    /// @notice A holder moves one of its seats; a live seat always moves (no Game read).
    function transferSeat(uint256 seed) external {
        ++calls[A_XFER];
        uint256 pickH = seed % (N_WALLETS + 2);
        address from = pickH < N_WALLETS ? wallets[pickH] : (pickH == N_WALLETS ? phantom : address(vault));
        uint256 len = seatsOf[from].length;
        if (len == 0) return;
        uint256 serial = seatsOf[from][(seed >> 8) % len];
        address to = _recipient(seed >> 16);
        if (from == address(vault)) {
            vm.prank(CREATOR);
            try vault.afkingSeatTransfer(serial, to) {} catch {
                _violate("the vault could not move a seat it holds");
                return;
            }
        } else {
            vm.prank(from);
            try token.transferFrom(from, to, serial) {} catch {
                _violate("a holder could not move a live seat");
                return;
            }
        }
        _gRemove(serial);
        _gAdd(serial, to);
        ++oks[A_XFER];
        _syncMints(0, token.freeClaims());
        _checkLive();
    }

    /// @notice Advance a day and crank until no work: process passes evict the unfunded.
    function driveDay(uint256) external {
        ++calls[A_DAY];
        vm.warp(block.timestamp + 1 days);
        for (uint256 i; i < 300; ++i) {
            _fulfill();
            try game.mineFlip(0) {
                ++dayCranks;
            } catch (bytes memory r) {
                if (r.length == 4 && bytes4(r) == RNG_NOT_READY && _fulfill()) continue;
                if (!(r.length == 4 && bytes4(r) == NO_WORK)) _noteRevert(A_DAY, r);
                break;
            }
        }
        ++oks[A_DAY];
        _syncMints(0, token.freeClaims());
        _checkLive();
    }

    function mineFlip(uint256) external {
        ++calls[A_MINE];
        _fulfill();
        try game.mineFlip(0) {
            ++oks[A_MINE];
        } catch (bytes memory r) {
            _noteRevert(A_MINE, r);
        }
        _syncMints(0, token.freeClaims());
        _checkLive();
    }

    function _fulfill() internal returns (bool) {
        uint256 reqId = vrf.lastRequestId();
        if (reqId == 0) return false;
        (,, bool fulfilled) = vrf.pendingRequests(reqId);
        if (fulfilled) return false;
        try vrf.fulfillRandomWords(reqId, uint256(keccak256(abi.encode("seatcap", ++salt))) | 1) {
            return true;
        } catch {
            return false;
        }
    }

    // ═════════════════════════ the invariant ═════════════════════════

    /// @notice Empty when every seat/set bound holds, else the first broken one.
    function check() external view returns (string memory) {
        if (violations != 0) return firstViolation;
        uint256 l = token.totalSupply();
        uint256 s = game.subscriberSetLength();
        (uint256 e, bool sdgnrsIn, bool consistent) = exemptEntries();
        if (!consistent) return "set element does not match its Sub position";
        if (!sdgnrsIn) return "SDGNRS left the set";
        if (e != 2) return "VAULT left the set";
        if (s > CAP) return "S > 2000";
        if (l + s > CAP) return "L + S > 2000";
        uint256 serials = uint256(token.nextSerial()) - 1;
        if (serials < gBurns || l != serials - gBurns) return "L != (nextSerial - 1) - burns";
        if (l != gLive) return "L != ghost live count";
        if (uint256(token.nextSerial()) != gNext) return "nextSerial != ghost";
        uint256 sum;
        for (uint256 i; i < holders.length; ++i) {
            uint256 b = token.balanceOf(holders[i]);
            if (b != seatsOf[holders[i]].length) return "holder balance != ghost";
            sum += b;
        }
        if (sum != l) return "L != sum of holder balances";
        if (gInsertions > gBurns) return "non-exempt insertions > burns";
        if (token.freeClaims() > 1000) return "freeClaims > 1000";
        if (gFree != token.freeClaims()) return "freeClaims != ghost free mints";
        for (uint256 i; i < burnedSerials.length; ++i) {
            try token.ownerOf(burnedSerials[i]) returns (address) {
                return "a burned serial is owned again";
            } catch {}
        }
        for (uint256 i; i < phantomLo.length; ++i) {
            try token.ownerOf(phantomLo[i]) returns (address) {
                return "a burned serial is owned again";
            } catch {}
            try token.ownerOf(phantomHi[i] - 1) returns (address) {
                return "a burned serial is owned again";
            } catch {}
        }
        return "";
    }

    function actionName(uint256 a) external pure returns (string memory) {
        if (a == A_PASS) return "passPurchase";
        if (a == A_SMURF) return "createSmurf";
        if (a == A_APPROVE) return "approveOperator";
        if (a == A_VMINT) return "vaultMint";
        if (a == A_FFWD) return "fastForward";
        if (a == A_SUB) return "subscribe";
        if (a == A_UNDERFUND) return "underfund";
        if (a == A_VAULTSUB) return "vaultSubscription";
        if (a == A_XFER) return "transferSeat";
        if (a == A_DAY) return "driveDay";
        return "mineFlip";
    }
}
