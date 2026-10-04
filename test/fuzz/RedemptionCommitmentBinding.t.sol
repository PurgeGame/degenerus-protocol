// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";

/// @notice Current public burn/request/fulfill/resolve/permissionless-claim proof.
/// Initial soulbound balances come from the creator's real unwrap, and mock stETH
/// is transferred as backing. No protocol storage/runtime writes or mocked claims.
/// Two different burn sizes freeze independent bases, scores and FLIP escrows.
/// Known words cover real ticket/sDGNRS boxes plus winning and losing escrow.
/// Claims delayed past another real daily draw must retain their original day+1
/// word; later-day burns and donated backing must not rewrite old claims.
///
/// The keeper settles live claims in the call that finishes the daily work, as far as its
/// allowance admits, and a later-day burn or a fresh draw waits for the live cohort; so earlier
/// one-chunk padding claims head the FIFO queue, the probed keeper allowance stops at the
/// redemption stage with both owners unsettled, and the perturbations run inside that stage.
///
/// Scope: level zero, score-zero unboosted one-chunk redemptions with stETH custody,
/// ticket/sDGNRS reward branches. Boon formulas, other reward branches, 5-ETH chunk
/// chaining, bonus EV caps, wrapped burns, ETH custody and terminal settlement are
/// separate properties. Live pools and next-day credit placement are reconciled,
/// not assumed immutable across days or successful public mutations.
contract RedemptionCommitmentBindingTest is DeployProtocol {
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant DONOR = address(0xD0110);
    address private constant KEEPER = address(0xC0DE);
    uint256 private constant WIN_WORD = 7419;
    uint256 private constant LOSS_WORD = 7076;
    uint256 private constant BURN_A = 1_000_000_000 ether;
    uint256 private constant BURN_B = 2_000_000_000 ether;
    uint256 private constant BOX_TAG = 0x526564656d7074696f6e426f78;
    uint256 private constant PADS = 30;
    uint256 private constant PAD_BURN = 500_000_000 ether;

    struct Claim {
        uint256 base;
        uint256 score;
        uint256 escrow;
    }

    struct Award {
        uint256[51] entries;
        uint256 dgnrs;
        uint256 flip;
        uint256 direct;
        uint256 box;
    }

    struct Balance {
        uint256[51] entries;
        uint256 dgnrs;
        uint256 flip;
        uint256 liquid;
        uint256 claimable;
        uint256 eth;
        uint256 steth;
        uint256 wwxrp;
    }

    struct Ledger {
        uint256 future;
        uint256 next;
        uint256 current;
        uint256 liability;
        uint256 reservation;
        uint256 gameSteth;
        uint256 deskSteth;
        uint256 gameEth;
        uint256 deskEth;
        uint256 inventory;
        uint256 keeperFlip;
    }

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        _request();
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), 0xB007);
        _finish();
        dgnrs.unwrapTo(ALICE, 10_000_000_000 ether);
        dgnrs.unwrapTo(BOB, 10_000_000_000 ether);
        for (uint256 i; i < PADS; ++i) dgnrs.unwrapTo(_pad(i), 600_000_000 ether);
        mockStETH.mint(address(this), 2000 ether);
        assertTrue(mockStETH.transfer(address(sdgnrs), 2000 ether));
        mockStETH.mint(DONOR, 100 ether);
        vm.deal(ALICE, 100 ether);
        vm.deal(BOB, 100 ether);
        assertEq(game.level(), 0);
        assertEq(game.playerActivityScore(ALICE), 0);
        assertEq(game.playerActivityScore(BOB), 0);
    }

    function _request() private {
        for (uint256 i; i < 50 && !game.rngLocked(); ++i) {
            game.mineFlip();
        }
        assertTrue(game.rngLocked(), "actual daily request required");
        (,, bool fulfilled) = mockVRF.pendingRequests(mockVRF.lastRequestId());
        assertFalse(fulfilled);
    }

    function _finish() private {
        for (uint256 i; i < 100 && game.rngLocked(); ++i) {
            game.mineFlip();
        }
        assertFalse(game.rngLocked(), "bounded public daily resolution required");
    }

    function _pad(uint256 i) private pure returns (address) {
        return address(uint160(0xFADD00 + i));
    }

    /// @dev Advance with bounded allowances until the redemption consumer stage opens with both
    ///      owners unsettled. The engine admits chunks while the allowance covers the next declared
    ///      bound, so the call that finishes the daily work settles queue heads with its spare gas;
    ///      a step that reaches the owners is replayed with a smaller allowance.
    function _toRedemptionStage(uint24 day) private {
        for (uint256 i; i < 200 && game.rngConsumerStage() != 1; ++i) {
            uint256 snap = vm.snapshotState();
            bool stepped;
            for (uint256 g = 9_000_000; g >= 400_000 && !stepped; g -= 100_000) {
                try game.mineFlip{gas: g}() {
                    if (_claimState(ALICE, day).base != 0 && _claimState(BOB, day).base != 0) stepped = true;
                    else assertTrue(vm.revertToState(snap));
                } catch {
                    assertTrue(vm.revertToState(snap));
                }
            }
            assertTrue(stepped, "harness: a bounded allowance stops at the redemption stage");
        }
        assertEq(game.rngConsumerStage(), 1, "redemption stage reached after daily work");
        assertFalse(game.rngLocked());
    }

    /// @dev Settle the padding claims still ahead of the owners, in FIFO order.
    function _settlePads(uint24 day) private {
        for (uint256 i; i < PADS; ++i) {
            if (_claimState(_pad(i), day).base != 0) sdgnrs.claimRedemption(_pad(i), day);
        }
    }

    /// @dev The keeper's cleanup of the drained cohort, then the rest of the session.
    function _finishSession() private {
        for (uint256 i; i < 100 && !game.rngComplete(); ++i) game.mineFlip();
        assertTrue(game.rngComplete(), "bounded public session completion");
        assertFalse(sdgnrs.redemptionSettlementPending(), "cohort cleared");
    }

    function _claimState(address owner, uint24 day) private view returns (Claim memory c) {
        (uint96 base, uint16 score, uint96 escrow) = sdgnrs.pendingRedemptions(owner, day);
        c = Claim(base, score, escrow);
    }

    function _assertClaim(address owner, uint24 day, Claim memory expected) private view {
        assertEq(
            keccak256(abi.encode(_claimState(owner, day))),
            keccak256(abi.encode(expected)),
            "exact owner/day claim fields"
        );
    }

    function _burn(address owner, uint256 amount, uint24 day) private returns (Claim memory c) {
        uint256 supply = sdgnrs.totalSupply();
        uint256 tokens = sdgnrs.balanceOf(owner);
        uint256 backing = address(sdgnrs).balance + mockStETH.balanceOf(address(sdgnrs))
            + game.claimableWinningsOf(address(sdgnrs)) - sdgnrs.pendingRedemptionEthValue();
        uint256 flipBacking = sdgnrs.flipReserve();
        c.base = (backing * amount / supply) / 1 gwei * 1 gwei;
        c.escrow = flipBacking * amount / supply / 1 ether;
        c.score = game.playerActivityScore(owner) + 1;
        uint256 reservation = sdgnrs.pendingRedemptionEthValue();
        vm.prank(owner);
        (uint256 ethOut, uint256 stethOut, uint256 flipOut) = sdgnrs.burn(amount);
        assertEq(ethOut + stethOut + flipOut, 0, "burn commits; it does not pay early");
        _assertClaim(owner, day, c);
        assertGt(c.base, 0, "real non-dust ETH base");
        assertGt(c.escrow, 0, "real contingent FLIP removed from backing");
        assertEq(sdgnrs.totalSupply(), supply - amount, "exact supply burn");
        assertEq(sdgnrs.balanceOf(owner), tokens - amount, "exact owner burn");
        assertEq(sdgnrs.flipReserve(), flipBacking - c.escrow * 1 ether, "escrow removed exactly once");
        assertEq(sdgnrs.pendingRedemptionEthValue(), reservation + c.base * 175 / 100, "full MAX reservation");
    }

    function _perturb(uint24 day, Claim memory a, Claim memory b) private {
        for (uint256 i; i < 2; ++i) {
            address owner = i == 0 ? ALICE : BOB;
            vm.prank(owner);
            game.purchase{value: 0.01 ether}(owner, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        }
        vm.prank(ALICE);
        game.placeDegeneretteBet{value: 0.01 ether}(ALICE, 0, 0.01 ether, 1, 17);
        uint256 beforeDonation = mockStETH.balanceOf(address(sdgnrs));
        vm.prank(DONOR);
        assertTrue(mockStETH.transfer(address(sdgnrs), 5 ether));
        assertEq(mockStETH.balanceOf(address(sdgnrs)), beforeDonation + 5 ether, "live backing really changed");
        if (game.rngLocked()) {
            vm.expectRevert(sDGNRS.BurnsBlockedDuringRng.selector);
            vm.prank(ALICE);
            sdgnrs.burn(1 ether);
        }
        _assertClaim(ALICE, day, a);
        _assertClaim(BOB, day, b);
        assertGt(game.playerActivityScore(ALICE), a.score - 1, "live score differs from frozen burn score");
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
    }

    function _seed(uint256 word, address owner) private pure returns (uint256) {
        uint256 entropy = uint256(keccak256(abi.encode(word, uint256(uint160(owner)))));
        return uint256(keccak256(abi.encode(entropy, owner, BOX_TAG)));
    }

    function _variance(uint256 seed) private pure returns (uint256) {
        uint256 roll = uint24(seed >> 96) % 10_000;
        uint256[6] memory cut = [uint256(0), 100, 500, 2500, 7000, 10_000];
        uint256[5] memory lo = [uint256(40_000), 20_000, 10_000, 5923, 3600];
        uint256[5] memory hi = [uint256(65_000), 35_000, 16_000, 9923, 7200];
        for (uint256 i; i < 5; ++i) {
            if (roll < cut[i + 1]) return lo[i] + (roll - cut[i]) * (hi[i] - lo[i]) / (cut[i + 1] - cut[i] - 1);
        }
        revert("invalid variance");
    }

    function _flipPercent(uint256 word, uint24 day) private pure returns (uint256) {
        uint256 r = uint256(keccak256(abi.encodePacked(keccak256("degenerus.coinflip.reward-percent"), word, day)));
        return (r % 20 == 0 ? 50 : r % 20 == 1 ? 150 : 78 + r % 38) + 2; // level-zero bonus
    }

    function _reference(uint256 word, address owner, uint24 day, Claim memory c, uint256 inventory)
        private
        pure
        returns (Award memory a)
    {
        uint256 rolled = c.base * (((word >> 8) % 151) + 25) / 100;
        a.direct = rolled / 2;
        a.box = rolled - a.direct;
        require(a.box >= 0.01 ether && a.box <= 5 ether, "fixture must materialize one real chunk");
        require(c.score == 1, "oracle intentionally covers frozen score zero");
        uint256 scaled = a.box * 9000 / 10_000;
        uint256 main = scaled - scaled * 1000 / 10_000;
        uint256 seed = _seed(word, owner);
        uint256 roll = uint16(seed >> 40) % 20;
        if (roll < 8) {
            uint256 target = uint16(seed) % 100 < 20 ? 6 + uint16(seed >> 24) % 46 : 1 + uint8(seed >> 16) % 5;
            require(target <= 4, "fixture uses near .01 ETH ticket tier");
            uint256 budget = (main * 19_678 / 10_000) * 8750 / 10_000;
            uint256 qty = (budget * _variance(seed) / 10_000) * 100 / 0.01 ether;
            uint256 whole = qty / 100;
            if (uint32(seed >> 224) % 100 < qty % 100) ++whole;
            a.entries[target - 1] = whole * 4;
        } else if (roll < 11) {
            uint256 tier = uint24(seed >> 56) % 1000;
            uint256 ppm = tier < 795 ? 10 : tier < 945 ? 390 : tier < 995 ? 800 : 8000;
            a.dgnrs = inventory * ppm * main / (1_000_000 * 1 ether);
            uint256 step = 1;
            while (a.dgnrs / step >= 1000) step *= 10;
            a.dgnrs = a.dgnrs / step * step;
            if (a.dgnrs > inventory) a.dgnrs = inventory;
        } else {
            revert("unsupported reward must never silently skip");
        }
        if (word & 1 != 0) {
            uint256 principal = c.escrow * 1 ether;
            // Credited as a coinflip stake, which books whole FLIP.
            a.flip = (principal + principal * _flipPercent(word, day + 1) / 100) / 1 ether * 1 ether;
        }
    }

    function _balance(address owner) private view returns (Balance memory s) {
        for (uint24 level = 1; level <= 51; ++level) {
            s.entries[level - 1] = game.entriesOwedView(level, owner);
        }
        s.dgnrs = sdgnrs.balanceOf(owner);
        s.flip = coinflip.coinflipAmount(owner);
        s.liquid = coin.balanceOf(owner);
        s.claimable = game.claimableWinningsOf(owner);
        s.eth = owner.balance;
        s.steth = mockStETH.balanceOf(owner);
        s.wwxrp = wwxrp.balanceOf(owner);
    }

    function _assertAward(address owner, Balance memory beforeState, Award memory expected) private view {
        Balance memory afterState = _balance(owner);
        for (uint256 i; i < 51; ++i) {
            assertEq(
                afterState.entries[i], beforeState.entries[i] + expected.entries[i], "actual owner/level box tickets"
            );
        }
        assertEq(afterState.dgnrs, beforeState.dgnrs + expected.dgnrs, "actual owner sDGNRS box award");
        assertEq(afterState.flip, beforeState.flip + expected.flip, "actual original-day contingent FLIP");
        assertEq(afterState.claimable, beforeState.claimable + expected.direct, "actual owner direct ETH credit");
        assertEq(afterState.liquid, beforeState.liquid);
        assertEq(afterState.eth, beforeState.eth, "permissionless claim cannot push claimant ETH");
        assertEq(afterState.steth, beforeState.steth);
        assertEq(afterState.wwxrp, beforeState.wwxrp);
    }

    function _ledger() private view returns (Ledger memory l) {
        l.future = game.futurePrizePoolView();
        l.next = game.nextPrizePoolView();
        l.current = game.currentPrizePoolView();
        l.liability = game.claimablePoolView();
        l.reservation = sdgnrs.pendingRedemptionEthValue();
        l.gameSteth = mockStETH.balanceOf(address(game));
        l.deskSteth = mockStETH.balanceOf(address(sdgnrs));
        l.gameEth = address(game).balance;
        l.deskEth = address(sdgnrs).balance;
        l.inventory = sdgnrs.poolBalance(sDGNRS.Pool.Lootbox);
        l.keeperFlip = coinflip.coinflipAmount(KEEPER);
    }

    function _claimPair(uint24 day, Award memory a, Award memory b, bool batch) private {
        Balance memory beforeA = _balance(ALICE);
        Balance memory beforeB = _balance(BOB);
        Ledger memory l = _ledger();
        if (batch) {
            // The batch must be the exact FIFO prefix: a stale or duplicate entry reverts the whole
            // batch atomically (it no longer skips), so nothing pays and no bounty accrues.
            address[] memory owners = new address[](4);
            owners[0] = ALICE;
            owners[1] = address(0xBAD);
            owners[2] = ALICE;
            owners[3] = BOB;
            vm.expectRevert(sDGNRS.RedemptionOutOfOrder.selector);
            vm.prank(KEEPER);
            sdgnrs.claimRedemptionMany(owners, day);
            assertEq(keccak256(abi.encode(_ledger())), keccak256(abi.encode(l)), "rejected batch pays nothing");
            owners = new address[](2);
            owners[0] = ALICE;
            owners[1] = BOB;
            vm.prank(KEEPER);
            sdgnrs.claimRedemptionMany(owners, day);
        } else {
            vm.prank(KEEPER);
            sdgnrs.claimRedemption(ALICE, day);
            _assertAward(ALICE, beforeA, a);
            Award memory zero;
            _assertAward(BOB, beforeB, zero);
            vm.roll(block.number + 1);
            vm.warp(block.timestamp + 1);
            vm.prank(DONOR);
            sdgnrs.claimRedemption(BOB, day);
        }
        _assertAward(ALICE, beforeA, a);
        _assertAward(BOB, beforeB, b);
        Claim memory empty;
        _assertClaim(ALICE, day, empty);
        _assertClaim(BOB, day, empty);
        uint256 total = a.direct + a.box + b.direct + b.box;
        assertEq(sdgnrs.pendingRedemptionEthValue(), l.reservation - total, "release only these two reservations");
        assertEq(mockStETH.balanceOf(address(sdgnrs)), l.deskSteth - total, "actual custody funds both full claims");
        assertEq(mockStETH.balanceOf(address(game)), l.gameSteth + total, "all claim backing reaches game");
        assertEq(address(sdgnrs).balance, l.deskEth);
        assertEq(address(game).balance, l.gameEth);
        assertEq(game.futurePrizePoolView(), l.future + a.box + b.box, "exact live box pool credit");
        assertEq(game.claimablePoolView(), l.liability + a.direct + b.direct, "exact direct liability credit");
        assertEq(game.nextPrizePoolView(), l.next);
        assertEq(game.currentPrizePoolView(), l.current);
        assertEq(
            sdgnrs.poolBalance(sDGNRS.Pool.Lootbox), l.inventory - a.dgnrs - b.dgnrs, "actual token inventory debit"
        );
        assertEq(
            coinflip.coinflipAmount(KEEPER),
            l.keeperFlip + (batch ? 4.8 ether : 0),
            "bounty only counts two distinct settled claims"
        );
        assertEq(game.claimableWinningsOf(KEEPER), 0);
        assertEq(sdgnrs.balanceOf(KEEPER), 0);
        // Consumed heads cannot be re-taken (exact FIFO head; was NoClaim / a no-op batch).
        vm.expectRevert(sDGNRS.RedemptionOutOfOrder.selector);
        vm.prank(KEEPER);
        sdgnrs.claimRedemption(ALICE, day);
        beforeA = _balance(ALICE);
        beforeB = _balance(BOB);
        l = _ledger();
        address[] memory replay = new address[](2);
        replay[0] = ALICE;
        replay[1] = BOB;
        vm.expectRevert(sDGNRS.RedemptionOutOfOrder.selector);
        vm.prank(KEEPER);
        sdgnrs.claimRedemptionMany(replay, day);
        Award memory none;
        _assertAward(ALICE, beforeA, none);
        _assertAward(BOB, beforeB, none);
        assertEq(keccak256(abi.encode(_ledger())), keccak256(abi.encode(l)), "replay cannot pay or release anything");
    }

    function _run(uint24 day, Claim memory a, Claim memory b, uint256 word, bool batch, bool perturb)
        private
        returns (bytes32)
    {
        vm.warp(block.timestamp + 1 days);
        _request();
        vm.expectRevert(sDGNRS.NotResolved.selector);
        vm.prank(KEEPER);
        sdgnrs.claimRedemption(ALICE, day);
        if (perturb) _perturb(day, a, b);
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), word);
        if (perturb) _perturb(day, a, b);
        _toRedemptionStage(day);
        uint16 roll = uint16(((word >> 8) % 151) + 25);
        assertEq(sdgnrs.redemptionPeriods(day), roll, "original period's independently computed roll");
        assertEq(game.rngWordForDay(day + 1), word, "original day+1 commitment recorded");
        _settlePads(day);
        assertEq(sdgnrs.pendingRedemptionEthValue(), (a.base + b.base) * roll / 100);
        if (perturb) {
            _perturb(day, a, b);
            // While this cohort is live, a later-day burn cannot enter and no fresh draw can be
            // requested: the claims settle against their original session before either.
            vm.expectRevert(sDGNRS.PriorDayUnresolved.selector);
            vm.prank(ALICE);
            sdgnrs.burn(100_000_000 ether);
            vm.expectRevert(bytes4(keccak256("RngNotReady()")));
            game.requestLootboxRng();
        }
        _assertClaim(ALICE, day, a);
        _assertClaim(BOB, day, b);
        assertEq(game.level(), 0, "hold legitimate live denomination fixed");
        assertEq(game.rngWordForDay(day + 1), word);
        assertEq(sdgnrs.redemptionPeriods(day), roll);
        (uint16 percent, bool won) = coinflip.getCoinflipDayResult(day + 1);
        assertEq(won, word & 1 != 0);
        assertEq(uint256(percent), won ? _flipPercent(word, day + 1) : 1, "absolute original coinflip result");
        uint256 inventory = sdgnrs.poolBalance(sDGNRS.Pool.Lootbox);
        Award memory awardA = _reference(word, ALICE, day, a, inventory);
        Award memory awardB = _reference(word, BOB, day, b, inventory - awardA.dgnrs);
        assertGt(awardA.entries[word == WIN_WORD ? 2 : 0], 0, "actual ticket branch witness");
        assertGt(awardB.dgnrs, 0, "actual token branch witness");
        assertGt(awardA.direct, 0);
        assertGt(awardB.direct, awardA.direct);
        _claimPair(day, awardA, awardB, batch);
        if (perturb) {
            // After the cohort clears, later-day burns and another real draw leave the settled
            // claims and their original resolution untouched.
            _finishSession();
            Claim memory laterA = _burn(ALICE, 100_000_000 ether, day + 1);
            Claim memory laterB = _burn(BOB, 200_000_000 ether, day + 1);
            Claim memory empty;
            _assertClaim(ALICE, day, empty);
            _assertClaim(BOB, day, empty);
            vm.warp(block.timestamp + 1 days);
            _request();
            uint256 laterWord = word & 1 == 0 ? 0xC0FF : 0xC0FE;
            mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), laterWord);
            _finish();
            assertEq(game.rngWordForDay(day + 2), laterWord);
            assertNotEq(laterWord, word);
            assertEq(sdgnrs.redemptionPeriods(day + 1), ((laterWord >> 8) % 151) + 25);
            assertNotEq(sdgnrs.redemptionPeriods(day + 1), roll, "new pool has a distinct resolution");
            assertEq(sdgnrs.redemptionPeriods(day), roll, "original resolution immutable");
            _assertClaim(ALICE, day, empty);
            _assertClaim(BOB, day, empty);
            assertGt(laterA.base + laterB.base, 0);
        }
        return keccak256(abi.encode(awardA, awardB));
    }

    function _compare(uint256 word, bool batch) private {
        uint24 day = uint24(game.currentDayView());
        for (uint256 i; i < PADS; ++i) {
            vm.prank(_pad(i));
            sdgnrs.burn(PAD_BURN);
        }
        Claim memory a = _burn(ALICE, BURN_A, day);
        Claim memory b = _burn(BOB, BURN_B, day);
        assertEq(a.score, 1);
        assertEq(b.score, 1);
        assertNotEq(a.base, b.base);
        assertNotEq(a.escrow, b.escrow);
        uint256 snap = vm.snapshotState();
        bytes32 baseline = _run(day, a, b, word, batch, false);
        assertTrue(vm.revertToState(snap));
        bytes32 delayed = _run(day, a, b, word, batch, true);
        assertEq(delayed, baseline, "old claim rewards retain original commitment after later burns/draws");
    }

    function testWinningDaySingleClaimsRemainBound() public {
        _compare(WIN_WORD, false);
    }

    function testWinningDayBatchClaimsRemainBound() public {
        _compare(WIN_WORD, true);
    }

    function testLosingDaySingleClaimsRemainBound() public {
        _compare(LOSS_WORD, false);
    }

    function testLosingDayBatchClaimsRemainBound() public {
        _compare(LOSS_WORD, true);
    }
}
