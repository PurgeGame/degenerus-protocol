// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {OwnerTargetCall} from "../helpers/OwnerTargetCall.sol";

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {AFKingSubscriptionToken} from "../../contracts/AFKingSubscriptionToken.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";

/// @title SeatFixture — shared fixture for the seat suites on a real protocol deploy.
/// @notice Seat grants, subscriptions by account ID, smurfs, operator approvals, day driving,
///         eviction, cap filling, and raw reads of the Game's subscriber set (the packed `_subscribers`
///         lanes and the `_subMeta` reverse lookup, validated against the views in setUp).
abstract contract SeatFixture is DeployProtocol {
    error E();
    error NotApproved();
    error RngLocked();
    error NotVaultOwner();

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    uint32 internal constant VAULT_ID = 1;
    uint32 internal constant SDGNRS_ID = 2;
    uint256 internal constant SUB_FUND = 0.05 ether;
    uint256 internal constant SEAT_CAP = 2000;
    bytes4 internal constant NO_WORK = bytes4(keccak256("NoWork()"));
    bytes4 internal constant RNG_NOT_READY = bytes4(keccak256("RngNotReady()"));

    uint256 internal _daySalt;
    uint256 internal _fillerNonce;

    function _setUpSeats() internal {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        mockVRF.fundSubscription(1, 1_000_000 ether);
        _checkSetLayout();
        _finishSubscriptionWindow();
    }

    // ─────────────────────────── raw set reads ───────────────────────────

    /// @dev Account `id`'s 85-bit subscriber lane and set position + 1 (0 = not in the set).
    function _laneOf(uint32 id) internal view returns (uint256 lane, uint256 position1) {
        return GameSlotKeys.subLane(address(game), id);
    }

    /// @dev The member's daily quantity (0 = no run: never subscribed, cancelled or evicted).
    function _qty(uint32 id) internal view returns (uint256) {
        return GameSlotKeys.subQuantity(address(game), id);
    }

    /// @dev The 1-indexed set position (0 = not in the set).
    function _pos(uint32 id) internal view returns (uint256 position1) {
        (, position1) = _laneOf(id);
    }

    /// @dev The wallet ID in physical set position `position` (boxes from 0, tickets descending from 2000).
    function _setElement(uint256 position) internal view returns (uint256) {
        bytes32 slot = bytes32(uint256(keccak256(abi.encode(GameSlots.SUBSCRIBERS))) + position / 3);
        return uint32(uint256(vm.load(address(game), slot)) >> ((position % 3) * 85));
    }

    /// @dev Whether account `id` sits in the set; cross-checks the element.
    function _inSet(uint32 id) internal view returns (bool) {
        uint256 p = _pos(id);
        if (p == 0) return false;
        uint256 el = _setElement(p - 1);
        require(el == id, "set element mismatch");
        return true;
    }

    /// @dev The Game's protocol subscription flags (bit 4 = Vault owner pause).
    function _flags() internal view returns (uint8) {
        return uint8(uint256(vm.load(address(game), bytes32(GameSlots.AFKING_PROTOCOL_FLAGS)))
            >> (8 * GameSlots.AFKING_PROTOCOL_FLAGS_OFFSET));
    }

    /// @dev VAULT / SDGNRS entries currently in the set.
    function _exemptEntries() internal view returns (uint256 e) {
        if (_inSet(VAULT_ID)) ++e;
        if (_inSet(SDGNRS_ID)) ++e;
    }

    function _S() internal view returns (uint256) {
        return game.subscriberSetLength();
    }

    function _L() internal view returns (uint256) {
        return afkingSubToken.totalSupply();
    }

    function _checkSetLayout() internal view {
        require(
            uint256(vm.load(address(game), bytes32(GameSlots.SUBSCRIBERS))) == game.subscriberSetLength(),
            "_subscribers root"
        );
        require(game.walletIdOf(address(vault)) == VAULT_ID, "vault wallet ID");
        require(game.walletIdOf(address(sdgnrs)) == SDGNRS_ID, "sdgnrs wallet ID");
        require(_inSet(VAULT_ID) && _inSet(SDGNRS_ID), "_subMeta root");
        require(_qty(VAULT_ID) == 1 && _qty(SDGNRS_ID) == 1, "lane quantity");
    }

    /// @dev A live run: a member that is not pending removal.
    function _activeId(uint32 id) internal view returns (bool) {
        (uint256 lane, uint256 position1) = _laneOf(id);
        return position1 != 0 && lane & (uint256(1) << 68) == 0;
    }

    function _active(address who) internal view returns (bool) {
        uint32 id = game.walletIdOf(who);
        return id != 0 && _activeId(id);
    }

    // ─────────────────────────── seats ───────────────────────────

    /// @dev A fresh seat for `who`: a free-tranche mint (the GAME-gated push mint a pass
    ///      purchase makes) while the tranche is open, else a vault mint. Read before a prank.
    function _giveSeat(address who) internal returns (uint256 seat) {
        if (afkingSubToken.freeClaims() < 1000) {
            vm.prank(ContractAddresses.GAME);
            afkingSubToken.mintSeatFor(who);
        } else {
            vm.prank(ContractAddresses.CREATOR);
            OwnerTargetCall.call(address(vault), abi.encodeCall(vault.afkingSeatMint, (who, 1)), 0);
        }
        seat = uint256(afkingSubToken.nextSerial()) - 1;
        require(afkingSubToken.ownerOf(seat) == who, "seat grant");
    }

    /// @dev A wallet that bought a lazy pass (registered, holding the pass's free seat).
    function _passBuyer(string memory tag) internal returns (address who, uint256 seat) {
        who = makeAddr(tag);
        vm.deal(who, 100 ether);
        seat = afkingSubToken.nextSerial();
        vm.prank(who);
        game.purchaseLazyPass{value: 0.24 ether}(0, bytes32(0));
        require(afkingSubToken.ownerOf(seat) == who, "pass seat");
    }

    /// @dev Free-tranche mints to fresh fillers until `freeClaims == target`.
    function _fillFreeTrancheTo(uint256 target) internal {
        while (afkingSubToken.freeClaims() < target) {
            vm.prank(ContractAddresses.GAME);
            afkingSubToken.mintSeatFor(address(uint160(0xF1110000 + (++_fillerNonce))));
        }
    }

    /// @dev Vault mint (as the vault owner) that leaves `L + S == SEAT_CAP - headroom`.
    function _mintToCap(address to, uint256 headroom) internal {
        uint256 n = SEAT_CAP - headroom - _L() - _S();
        if (n == 0) return;
        vm.prank(ContractAddresses.CREATOR);
        OwnerTargetCall.call(address(vault), abi.encodeCall(vault.afkingSeatMint, (to, n)), 0);
        assertEq(_L() + _S(), SEAT_CAP - headroom, "fixture: sum at the target");
    }

    // ─────────────────────────── accounts ───────────────────────────

    function _createSmurf(address owner) internal returns (uint32 smurfId) {
        uint256 price = game.mintPrice();
        vm.deal(owner, owner.balance + price);
        vm.prank(owner);
        smurfId = game.createSmurf{value: price}(bytes32(0), MintPaymentKind.DirectEth);
    }

    /// @dev `caller` subscribes account `id` (0 = itself) in lootbox mode, quantity 1, naming
    ///      `seat`, with SUB_FUND attached.
    function _subscribe(address caller, uint32 id, uint256 seat) internal {
        vm.deal(caller, caller.balance + SUB_FUND);
        vm.prank(caller);
        game.subscribe{value: SUB_FUND}(id, false, 1, seat);
    }

    function _cancel(address caller, uint32 id) internal {
        vm.prank(caller);
        game.subscribe(id, false, 0, 0);
    }

    // ─────────────────────────── days ───────────────────────────

    /// @dev Advance one day and crank the state engine until it reports no work, fulfilling
    ///      every VRF request it opens.
    function _driveDay() internal {
        _finishReadConsumers();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        for (uint256 i; i < 400; ++i) {
            _fulfillPending();
            try game.mineFlip(0) {} catch (bytes memory reason) {
                bytes4 sel = bytes4(reason);
                if (reason.length == 4 && sel == NO_WORK) return;
                if (reason.length == 4 && sel == RNG_NOT_READY) {
                    if (!_fulfillPending()) return;
                    continue;
                }
                assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
            }
        }
    }

    function _fulfillPending() internal returns (bool) {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId == 0) return false;
        (,, bool fulfilled) = mockVRF.pendingRequests(reqId);
        if (fulfilled) return false;
        mockVRF.fulfillRandomWords(reqId, uint256(keccak256(abi.encode("seat-day", ++_daySalt))) | 1);
        return true;
    }

    /// @dev Drive days until account `id` has left the set (expiry or seizure removal).
    function _driveUntilOut(uint32 id) internal {
        for (uint256 d; d < 8 && _pos(id) != 0; ++d) _driveDay();
        require(_pos(id) == 0, "fixture: entry left the set");
    }

    /// @dev Strip account `id`'s funding (afking and claimable) as `caller` and drive days until
    ///      the subscriber pass expires it.
    function _evict(address caller, uint32 id) internal {
        (address key,,) = game.resolveAccount(id, caller);
        for (uint256 d; d < 8 && _pos(id) != 0; ++d) {
            uint256 rem = game.afkingFundingOf(key);
            if (rem != 0) {
                vm.prank(caller);
                game.withdrawAfkingFunding(id, rem);
            }
            if (game.claimableWinningsOf(key) > 1) {
                vm.prank(caller);
                game.claimWinnings(id);
            }
            _driveDay();
        }
        require(_pos(id) == 0, "fixture: the funding-kill evicted the sub");
        require(_qty(id) == 0, "fixture: evicted lane deleted");
    }
}

/// @title SeatConsumption — the one-seat-per-subscription model on a real deploy (plan F,
///        decisions G6; F-token notes §6 seat bullets 1–6 and O1; F-game test item 9).
/// @notice A new run burns exactly one seat held by the subscriber's payee; a change, a cancel
///         and the exempt VAULT/SDGNRS subscriptions burn nothing; a vault mint is refused while
///         the free tranche is open and whenever live seats + set length would pass 2,000; an
///         ended run frees exactly one vault mint the moment it leaves the set (a cancel removes
///         it at once); transfers never read the Game. The Vault's quantity 0 is a pause that
///         keeps its entry, so pause and resume cannot take the combined count past the cap.
contract SeatConsumptionTest is SeatFixture {
    address internal op = makeAddr("seat-operator");

    function setUp() public {
        _setUpSeats();
        vm.deal(op, 100 ether);
    }

    function _expectBurn(address holder, uint256 seat) internal {
        vm.expectCall(
            address(afkingSubToken),
            abi.encodeCall(AFKingSubscriptionToken.consumeSeat, (holder, seat)),
            1
        );
        vm.expectEmit(true, true, true, true, address(afkingSubToken));
        emit Transfer(holder, address(0), seat);
    }

    function _expectNoBurn() internal {
        vm.expectCall(
            address(afkingSubToken),
            abi.encodeWithSelector(AFKingSubscriptionToken.consumeSeat.selector),
            0
        );
    }

    // ═══════════════ Bullet 1: a new run burns exactly one payee seat ═══════════════

    function test_ownerSelfSubscribeBurnsTheNamedSeat() public {
        (address p, uint256 seat) = _passBuyer("self-sub");
        uint256 spare = _giveSeat(p);
        uint256 l0 = _L();
        uint256 s0 = _S();

        _expectBurn(p, seat);
        _subscribe(p, 0, seat);

        assertEq(afkingSubToken.balanceOf(p), 1, "one of two seats burned");
        assertEq(afkingSubToken.ownerOf(spare), p, "the unnamed seat stays");
        assertEq(_L(), l0 - 1, "live seats - 1");
        assertEq(_S(), s0 + 1, "set + 1");
        vm.expectRevert(AFKingSubscriptionToken.InvalidToken.selector);
        afkingSubToken.ownerOf(seat);
        assertTrue(_active(p), "run started");
    }

    function test_smurfSubscribeByOwnerBurnsTheOwnersSeat() public {
        (address owner, uint256 seat) = _passBuyer("smurf-owner");
        _grantSmurfBase(owner, 1);
        uint32 smurfId = _createSmurf(owner);
        uint256 l0 = _L();

        _expectBurn(owner, seat);
        _subscribe(owner, smurfId, seat);

        assertTrue(_activeId(smurfId), "smurf run started");
        assertTrue(_inSet(smurfId), "subaccount ID in the set");
        assertEq(afkingSubToken.balanceOf(owner), 0, "owner's seat burned");
        assertEq(_L(), l0 - 1);
        assertFalse(_active(owner), "the owner's own account is not subscribed");
    }

    function test_smurfSubscribeByOperatorBurnsTheOwnersSeat() public {
        (address owner, uint256 seat) = _passBuyer("smurf-owner-op");
        _grantSmurfBase(owner, 1);
        uint32 smurfId = _createSmurf(owner);
        vm.prank(owner);
        game.setOperatorApproval(smurfId, op, true);
        assertEq(afkingSubToken.getApproved(seat), address(0), "no ERC721 approval");
        assertFalse(afkingSubToken.isApprovedForAll(owner, op), "no ERC721 operator");

        _expectBurn(owner, seat);
        _subscribe(op, smurfId, seat);

        assertTrue(_inSet(smurfId), "operator started the smurf's run");
        assertEq(afkingSubToken.balanceOf(owner), 0, "owner's seat burned by the operator");
    }

    function test_operatorSubscribingAWalletBurnsItsSeatWithoutErc721Approval() public {
        (address x, uint256 seat) = _passBuyer("op-wallet");
        uint32 xId = game.walletIdOf(x);
        uint256 f0 = game.afkingFundingOf(x);
        vm.prank(x);
        game.setOperatorApproval(0, op, true);
        assertEq(afkingSubToken.getApproved(seat), address(0));
        assertFalse(afkingSubToken.isApprovedForAll(x, op));

        _expectBurn(x, seat);
        _subscribe(op, xId, seat);

        assertTrue(_active(x), "operator started X's run");
        assertEq(afkingSubToken.balanceOf(x), 0, "X's seat burned");
        assertGt(game.afkingFundingOf(x), f0, "the operator's ETH funds X's bucket");
        assertEq(game.afkingFundingOf(op), 0, "nothing in the operator's bucket");
    }

    /// @notice Another holder's seat, a burned seat, a never-minted serial and serial 0 all
    ///         revert InvalidToken, and the whole call unwinds: no Sub, no set entry, no
    ///         funding credit, no registration.
    function test_wrongSeatRevertsAndLeavesNothing() public {
        (address other, uint256 otherSeat) = _passBuyer("other-holder");
        (address burner, uint256 burnSeat) = _passBuyer("burner");
        _subscribe(burner, 0, burnSeat);

        address fresh = makeAddr("fresh-no-id");
        (address registered,) = _passBuyer("registered");
        uint32 regId = game.walletIdOf(registered);
        uint256 never = uint256(afkingSubToken.nextSerial()) + 50;
        uint256[4] memory bad = [otherSeat, burnSeat, never, uint256(0)];

        uint256 s0 = _S();
        uint256 l0 = _L();
        uint256 regFunding = game.afkingFundingOf(registered);
        for (uint256 i; i < 4; ++i) {
            vm.deal(fresh, 1 ether);
            vm.prank(fresh);
            vm.expectRevert(AFKingSubscriptionToken.InvalidToken.selector);
            game.subscribe{value: SUB_FUND}(0, false, 1, bad[i]);

            vm.prank(registered);
            vm.expectRevert(AFKingSubscriptionToken.InvalidToken.selector);
            game.subscribe{value: SUB_FUND}(0, false, 1, bad[i]);
        }
        assertEq(game.walletIdOf(fresh), 0, "registration unwound");
        assertEq(game.afkingFundingOf(fresh), 0, "no funding credit (fresh)");
        assertEq(_pos(regId), 0, "no lane");
        assertEq(game.afkingFundingOf(registered), regFunding, "no funding credit (registered)");
        assertEq(_S(), s0, "no set entry");
        assertEq(_L(), l0, "no seat burned");
        assertEq(afkingSubToken.ownerOf(otherSeat), other, "other holder untouched");
    }

    // ═══════════════ Bullet 2: changes and cancels burn nothing ═══════════════

    function test_liveRunChangeWithGarbageSeatBurnsNothing() public {
        (address p, uint256 seat) = _passBuyer("changer");
        _subscribe(p, 0, seat);
        uint32 id = game.walletIdOf(p);
        uint256 l0 = _L();
        uint256 s0 = _S();

        _expectNoBurn();
        vm.prank(p);
        game.subscribe(0, true, 3, 424242);

        assertEq(_qty(id), 3, "run changed");
        assertEq(_L(), l0, "no seat burned");
        assertEq(_S(), s0, "no set change");
    }

    function test_cancelBurnsNothingAndRemovesAtOnce() public {
        (address p, uint256 seat) = _passBuyer("canceller");
        uint256 spare = _giveSeat(p);
        _subscribe(p, 0, seat);
        uint32 id = game.walletIdOf(p);
        uint256 l0 = _L();
        uint256 s0 = _S();

        _expectNoBurn();
        vm.prank(p);
        game.subscribe(0, false, 0, spare);

        assertEq(_qty(id), 0, "no run");
        assertEq(_pos(id), 0, "removed from the set at once");
        assertEq(_S(), s0 - 1, "set length drops by one: no tombstone");
        assertEq(_L(), l0, "no seat burned");
        assertEq(afkingSubToken.ownerOf(spare), p, "named seat untouched");
    }

    /// @notice Cancel then re-subscribe the same day: the new run burns another seat and the set returns
    ///         to its length. The first (burned) seat cannot be named again.
    function test_resubscribeAfterCancelBurnsOneSeat() public {
        (address p, uint256 seat) = _passBuyer("cancel-rerun");
        uint256 second = _giveSeat(p);
        _subscribe(p, 0, seat);
        uint256 sLive = _S();
        _cancel(p, 0);
        uint32 id = game.walletIdOf(p);
        assertEq(_S(), sLive - 1, "the cancel removed the entry");
        uint256 l0 = _L();

        vm.deal(p, p.balance + SUB_FUND);
        vm.prank(p);
        vm.expectRevert(AFKingSubscriptionToken.InvalidToken.selector);
        game.subscribe{value: SUB_FUND}(0, false, 1, seat);

        _expectBurn(p, second);
        _subscribe(p, 0, second);

        assertEq(_qty(id), 1, "run restarted");
        assertEq(_S(), sLive, "set length back to the live count");
        assertEq(_L(), l0 - 1, "exactly one more seat burned");
    }

    function test_resubscribeAfterADayBurnsOneSeatAndAddsToTheSet() public {
        (address p, uint256 seat) = _passBuyer("day-rerun");
        uint256 second = _giveSeat(p);
        _subscribe(p, 0, seat);
        _cancel(p, 0);
        uint256 sCancelled = _S();
        _driveDay();
        assertEq(_S(), sCancelled, "the pass has nothing left to remove");

        uint256 l0 = _L();
        _expectBurn(p, second);
        _subscribe(p, 0, second);
        assertEq(_S(), sCancelled + 1, "set + 1");
        assertEq(_L(), l0 - 1, "one seat burned");
        assertTrue(_active(p));
    }

    function test_resubscribeAfterEvictionBurnsOneSeatAndAddsToTheSet() public {
        (address p, uint256 seat) = _passBuyer("evict-rerun");
        uint256 second = _giveSeat(p);
        _subscribe(p, 0, seat);
        uint32 id = game.walletIdOf(p);
        uint256 sLive = _S();
        _evict(p, id);
        assertEq(_S(), sLive - 1, "eviction removed the entry");
        assertEq(afkingSubToken.ownerOf(second), p, "eviction forfeits no seat");

        uint256 l0 = _L();
        _expectBurn(p, second);
        _subscribe(p, 0, second);
        assertEq(_S(), sLive, "set + 1");
        assertEq(_L(), l0 - 1, "one seat burned");
    }

    // ═══════════════ Bullet 3: exempt subscriptions never burn ═══════════════

    /// @notice VAULT and SDGNRS subscribed in their constructors, before the token existed (a
    ///         token call would have reverted the deploy); both construction seats are intact.
    function test_exemptConstructionSubscriptionsBurnedNothing() public view {
        assertEq(_L(), 2, "both construction seats live");
        assertEq(afkingSubToken.nextSerial(), 3, "nothing minted or burned since");
        assertEq(afkingSubToken.ownerOf(1), address(sdgnrs));
        assertEq(afkingSubToken.ownerOf(2), address(vault));
        assertEq(_S(), 2, "exactly the two exempt entries");
        assertTrue(_activeId(VAULT_ID) && _activeId(SDGNRS_ID), "both exempt runs live");
    }

    function _approveVaultOperator() internal {
        vm.prank(ContractAddresses.CREATOR);
        abi.decode(OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (
            ContractAddresses.GAME,
            abi.encodeWithSignature("setOperatorApproval(uint32,address,bool)", 0, op, true),
            0
        )), 0), (bytes));
    }

    /// @notice A change of the VAULT run through a vault-approved operator never calls
    ///         consumeSeat, even naming the vault's own seat.
    function test_vaultChangeThroughOperatorNeverCallsTheToken() public {
        _approveVaultOperator();
        _expectNoBurn();
        vm.prank(op);
        game.subscribe(VAULT_ID, false, 2, 2);
        assertEq(_qty(VAULT_ID), 2, "vault run changed");
        assertEq(afkingSubToken.ownerOf(2), address(vault), "vault seat untouched");
        assertEq(_L(), 2);
    }

    /// @notice The Vault's quantity 0 through the operator is the owner's pause: it never calls
    ///         consumeSeat, keeps the seat, the entry and the configured quantity, and sets the pause flag.
    function test_vaultPauseThroughOperatorNeverCallsTheToken() public {
        _approveVaultOperator();
        _expectNoBurn();
        vm.prank(op);
        game.subscribe(VAULT_ID, false, 0, 2);
        assertEq(_qty(VAULT_ID), 1, "the pause keeps the lane quantity");
        assertTrue(_inSet(VAULT_ID), "and the entry");
        assertTrue(_flags() & 4 != 0, "owner pause flag set");
        assertEq(afkingSubToken.ownerOf(2), address(vault), "vault seat untouched");
    }

    /// @notice Vault quantity zero retains its entry; a later resume burns no seat.
    function test_vaultResubscribeThroughOperatorNeverCallsTheToken() public {
        _approveVaultOperator();
        vm.prank(op);
        game.subscribe(VAULT_ID, false, 0, 0);
        _driveDay();
        assertTrue(_inSet(VAULT_ID), "zero-quantity Vault remains counted");
        uint256 s0 = _S();

        _expectNoBurn();
        vm.prank(op);
        game.subscribe(VAULT_ID, false, 1, 2);
        assertTrue(_inSet(VAULT_ID), "vault back in the set");
        assertEq(_S(), s0, "resume reuses the existing entry");
        assertEq(afkingSubToken.ownerOf(2), address(vault), "vault seat never burned");
        assertEq(_L(), 2);
    }

    // ═══════════════ Bullet 4: the vault mint's two gates ═══════════════

    function test_vaultMintRefusedUntilTheThousandthFreeSeat() public {
        _fillFreeTrancheTo(999);
        address to = makeAddr("grantee");
        vm.prank(ContractAddresses.CREATOR);
        vm.expectRevert(AFKingSubscriptionToken.FreeTrancheOpen.selector);
        OwnerTargetCall.call(address(vault), abi.encodeCall(vault.afkingSeatMint, (to, 1)), 0);

        _fillFreeTrancheTo(1000);
        vm.prank(ContractAddresses.CREATOR);
        OwnerTargetCall.call(address(vault), abi.encodeCall(vault.afkingSeatMint, (to, 1)), 0);
        assertEq(afkingSubToken.balanceOf(to), 1, "opens after the 1,000th free seat");
    }

    function test_vaultMintCapBoundary() public {
        (address p, uint256 seat) = _passBuyer("cap-sub");
        _subscribe(p, 0, seat);
        _fillFreeTrancheTo(1000);
        address to = makeAddr("cap-grantee");

        _mintToCap(to, 1);
        assertEq(_L() + _S(), 1999);

        vm.startPrank(ContractAddresses.CREATOR);
        vm.expectRevert(AFKingSubscriptionToken.SeatCapReached.selector);
        OwnerTargetCall.call(address(vault), abi.encodeCall(vault.afkingSeatMint, (to, 2)), 0); // would land on 2,001
        OwnerTargetCall.call(address(vault), abi.encodeCall(vault.afkingSeatMint, (to, 1)), 0); // lands on 2,000
        assertEq(_L() + _S(), 2000);
        vm.expectRevert(AFKingSubscriptionToken.SeatCapReached.selector);
        OwnerTargetCall.call(address(vault), abi.encodeCall(vault.afkingSeatMint, (to, 1)), 0);
        vm.stopPrank();
    }

    function test_vaultMintOfNReachingExactlyTheCapSucceeds() public {
        _fillFreeTrancheTo(1000);
        address to = makeAddr("cap-n");
        uint256 room = SEAT_CAP - _L() - _S();
        vm.prank(ContractAddresses.CREATOR);
        vm.expectRevert(AFKingSubscriptionToken.SeatCapReached.selector);
        OwnerTargetCall.call(address(vault), abi.encodeCall(vault.afkingSeatMint, (to, room + 1)), 0);
        vm.prank(ContractAddresses.CREATOR);
        OwnerTargetCall.call(address(vault), abi.encodeCall(vault.afkingSeatMint, (to, room)), 0);
        assertEq(_L() + _S(), SEAT_CAP, "one call lands exactly on the cap");
        assertEq(afkingSubToken.balanceOf(to), room);
    }

    function test_vaultMintOfZeroIsANoOpWithNoTokenCall() public {
        vm.expectCall(
            address(afkingSubToken),
            abi.encodeWithSelector(AFKingSubscriptionToken.vaultMintSeats.selector),
            0
        );
        vm.prank(ContractAddresses.CREATOR);
        OwnerTargetCall.call(address(vault), abi.encodeCall(vault.afkingSeatMint, (makeAddr("zero"), 0)), 0);
        assertEq(afkingSubToken.nextSerial(), 3, "nothing minted");
    }

    // ═══════════════ Bullet 5: a run that leaves the set frees one mint ═══════════════

    function test_endedRunFreesExactlyOneVaultMintOnceOutOfTheSet() public {
        (address a, uint256 seatA) = _passBuyer("ender-cancel");
        (address b, uint256 seatB) = _passBuyer("ender-evict");
        _subscribe(a, 0, seatA);
        vm.deal(b, 10 ether);
        vm.prank(b);
        game.subscribe{value: 1 ether}(0, false, 1, seatB);
        uint32 idA = game.walletIdOf(a);
        uint32 idB = game.walletIdOf(b);
        _fillFreeTrancheTo(1000);
        address to = makeAddr("freed-grantee");
        _mintToCap(to, 0);

        vm.startPrank(ContractAddresses.CREATOR);
        vm.expectRevert(AFKingSubscriptionToken.SeatCapReached.selector);
        OwnerTargetCall.call(address(vault), abi.encodeCall(vault.afkingSeatMint, (to, 1)), 0);
        vm.stopPrank();

        // A cancel removes the entry at once: exactly one mint.
        _cancel(a, 0);
        assertTrue(_pos(idA) == 0, "A left the set");
        assertTrue(_pos(idB) != 0, "B still live");
        vm.startPrank(ContractAddresses.CREATOR);
        OwnerTargetCall.call(address(vault), abi.encodeCall(vault.afkingSeatMint, (to, 1)), 0);
        vm.expectRevert(AFKingSubscriptionToken.SeatCapReached.selector);
        OwnerTargetCall.call(address(vault), abi.encodeCall(vault.afkingSeatMint, (to, 1)), 0);
        vm.stopPrank();

        // The unfunded expiry removes B: exactly one more.
        _evict(b, idB);
        vm.startPrank(ContractAddresses.CREATOR);
        OwnerTargetCall.call(address(vault), abi.encodeCall(vault.afkingSeatMint, (to, 1)), 0);
        vm.expectRevert(AFKingSubscriptionToken.SeatCapReached.selector);
        OwnerTargetCall.call(address(vault), abi.encodeCall(vault.afkingSeatMint, (to, 1)), 0);
        vm.stopPrank();
        assertEq(_L() + _S(), SEAT_CAP, "back at the cap");
    }

    // ═══════════════ Bullet 6: transfers read nothing from the Game ═══════════════

    function test_seatTransfersNeverCallTheGame() public {
        (address p, uint256 s1) = _passBuyer("mover");
        uint256 s2 = _giveSeat(p);
        uint256 s3 = _giveSeat(p);
        address to = makeAddr("mover-to");
        vm.expectCall(address(game), "", 0);
        vm.startPrank(p);
        afkingSubToken.transferFrom(p, to, s1);
        afkingSubToken.safeTransferFrom(p, to, s2);
        afkingSubToken.safeTransferFrom(p, to, s3, "");
        vm.stopPrank();
        assertEq(afkingSubToken.balanceOf(to), 3);
    }

    function test_activeSubscribersLastSeatMovesWithTheGameBroken() public {
        (address p, uint256 seat) = _passBuyer("broken-game");
        uint256 last = _giveSeat(p);
        _subscribe(p, 0, seat);
        assertEq(afkingSubToken.balanceOf(p), 1, "one seat left");
        address to = makeAddr("broken-to");

        uint256 snap = vm.snapshotState();
        vm.etch(address(game), hex"fe");
        vm.prank(p);
        afkingSubToken.transferFrom(p, to, last);
        assertEq(afkingSubToken.ownerOf(last), to, "moved with the Game unreachable");
        vm.revertToState(snap);
    }

    function test_activeSubscriberMayTransferEverySeatAndKeepsRunning() public {
        (address p, uint256 seat) = _passBuyer("seller");
        uint256 x = _giveSeat(p);
        uint256 y = _giveSeat(p);
        vm.deal(p, 10 ether);
        vm.prank(p);
        game.subscribe{value: 1 ether}(0, false, 1, seat);
        address buyer = makeAddr("seat-buyer");
        vm.startPrank(p);
        afkingSubToken.transferFrom(p, buyer, x);
        afkingSubToken.transferFrom(p, buyer, y);
        vm.stopPrank();
        assertEq(afkingSubToken.balanceOf(p), 0, "holds no seat");
        assertTrue(_active(p), "still subscribed");

        uint32 id = game.walletIdOf(p);
        _driveDay();
        _driveDay();
        assertTrue(_active(p) && _pos(id) != 0, "the run keeps running without a seat");
    }

    function test_vaultMovesItsConstructionSeatAndKeepsItsSubscription() public {
        address x = makeAddr("seat-two");
        address y = makeAddr("seat-two-swept");
        vm.prank(ContractAddresses.CREATOR);
        OwnerTargetCall.call(address(vault), abi.encodeCall(vault.sweepNft, (ContractAddresses.AFKING_SUB_TOKEN, x, 2)), 0);
        assertEq(afkingSubToken.ownerOf(2), x, "sweepNft moves serial 2");
        assertTrue(_inSet(VAULT_ID) && _activeId(VAULT_ID), "vault run untouched");

        vm.prank(x);
        afkingSubToken.transferFrom(x, address(vault), 2);
        vm.prank(ContractAddresses.CREATOR);
        OwnerTargetCall.call(address(vault), abi.encodeCall(vault.sweepNft, (address(afkingSubToken), y, 2)), 0);
        assertEq(afkingSubToken.ownerOf(2), y, "sweepNft moves serial 2");

        _driveDay();
        assertTrue(_inSet(VAULT_ID) && _activeId(VAULT_ID), "vault run keeps running");
    }

    // ═══════════════ F-game item 9 extras ═══════════════

    function test_vaultPauseAndResumeKeepCombinedCapAtTwoThousand() public {
        vm.prank(ContractAddresses.CREATOR);
        abi.decode(OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (
            ContractAddresses.GAME,
            abi.encodeWithSignature("setOperatorApproval(uint32,address,bool)", 0, op, true),
            0
        )), 0), (bytes));
        _fillFreeTrancheTo(1000);

        vm.prank(op);
        game.subscribe(VAULT_ID, false, 0, 0);
        _driveDay();
        assertTrue(_inSet(VAULT_ID), "zero-quantity Vault remains counted");
        assertEq(_exemptEntries(), 2, "both protocol entries remain");

        address to = makeAddr("o1-grantee");
        _mintToCap(to, 0);
        assertEq(_L() + _S(), 2000);

        vm.prank(op);
        game.subscribe(VAULT_ID, false, 1, 0);
        assertEq(_exemptEntries(), 2, "VAULT re-entered");
        assertEq(_L() + _S(), 2000, "resume cannot exceed the cap");

        vm.prank(ContractAddresses.CREATOR);
        vm.expectRevert(AFKingSubscriptionToken.SeatCapReached.selector);
        OwnerTargetCall.call(address(vault), abi.encodeCall(vault.afkingSeatMint, (to, 1)), 0);

        uint256 n = _S() - _exemptEntries();
        assertLe(_S(), 2000, "set bound");
        assertLe(_L() + n + 1, 2000, "non-exempt bound");
        assertGe(afkingSubToken.balanceOf(address(sdgnrs)), 1, "seat 1 stays live");
    }

    /// @notice SDGNRS's account cannot be acted for: no operator can be approved for ID 2 and a
    ///         stranger cannot cancel it, so its set entry is permanent.
    function test_sdgnrsEntryIsPermanent() public {
        vm.prank(op);
        vm.expectRevert(NotApproved.selector);
        game.setOperatorApproval(SDGNRS_ID, op, true);
        vm.prank(op);
        vm.expectRevert(NotApproved.selector);
        game.subscribe(SDGNRS_ID, false, 0, 0);
        assertTrue(_inSet(SDGNRS_ID));
    }

}
