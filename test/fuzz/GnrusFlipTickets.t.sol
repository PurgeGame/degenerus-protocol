// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {CoinflipStakeSetter} from "../helpers/CoinflipStakeSetter.sol";


contract GnrusTicketHost is DegenerusGame {
    function prime(uint24 next, uint8 mode) external returns (uint24 day) {
        day = _wallDay();
        // Jumping over launch must also retire its constructor-seeded ticket cohorts.
        // Live play drains them before these two reusable queue slots reach later levels.
        for (uint24 lvl = 1; lvl <= 2; ++lvl) {
            _releaseTicketQueue(_tqWriteKey(lvl));
            _releaseTicketQueue(_tqReadKey(lvl));
        }
        level = next - 1;
        _sdgnrsBonusLevel = level;
        degenesisClosed = 7;
        dailyIdx = day - 1;
        dailyComplete = true;
        lastDailyCompletedAt = uint48(block.timestamp - 1 days);
        lastDailyRequestWallDay = day - 1;
        purchaseStartDay = day - (mode == 1 ? 1 : 3);
        lastPurchaseDay = mode == 0;
        jackpotPhaseFlag = false;
        rngLockedFlag = false;
        subsFullyProcessed = true;
        ticketsFullyProcessed = true;
        humanReadComplete = true;
        _afkingResetDay = day;
        _setRngComplete(true);
        _setRngSessionPublished(true);
        _clearRngRequest();
        rngWordCurrent = 777;
        _setPrizePools(mode == 2 ? 0 : uint128(1000000 ether), 0);
    }

    function wwxrpBoon() external {
        boonPacked[3].slot1 |= (uint256(3) | (uint256(dailyIdx) << 3)) << BP_WWXRP_LANE_SHIFT;
    }

    function buyOnly() external {
        (bool ok, bytes memory reason) = ContractAddresses.GAME_MINT_MODULE.delegatecall(
            abi.encodeWithSignature("redeemGnrusFlip()"));
        if (!ok) assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
    }

    function request() external {
        (bool ok, bytes memory reason) = ContractAddresses.GAME_RNG_MODULE.delegatecall(
            abi.encodeWithSignature("requestDailyRng_g8190(uint24)", _afkingResetDay));
        if (!ok) assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
    }

    function jackpotRequest() external { jackpotPhaseFlag = true; lastPurchaseDay = false; }
    function targetAndPool(uint128 target, uint128 excess) external {
        _setLevelPrizePool(level, target);
        _setPrizePools(target + excess + 1, 0);
    }
    function boundaryState() external view returns (bool locked, uint256 pool_, uint256 target) {
        return (rngLockedFlag, _getNextPrizePool(), _prizePoolTarget(level + 1));
    }
    function pool(uint128 next) external { _setPrizePools(next, 0); }
    function snap(uint8 shift) external { snapShift = shift; }
    function redemptionOpen() external view returns (bool) { return _ticketRedemptionOpen(); }
    function readEntries(uint24 lvl) external view returns (uint256) {
        uint80 packed = _entryPacked(_tqWriteKey(lvl), GNRUS_WALLET_ID);
        return uint256(uint32(packed >> 8)) * QTY_SCALE + uint8(packed);
    }

    function committedEntries(uint24 lvl) external view returns (uint256) {
        uint80 packed = _entryPacked(_tqReadKey(lvl), GNRUS_WALLET_ID);
        return uint256(uint32(packed >> 8)) * QTY_SCALE + uint8(packed);
    }
}

contract GnrusFlipSeeder is CoinflipStakeSetter {
    function cursor() external view returns (uint24) { return playerState[3].lastClaim; }

    function stake(uint24 day) external view returns (uint256) { return _flipStake(day, 3); }

    function pendingResult(uint24 day, bool win) external {
        playerState[3].lastClaim = day - 1;
        _storeDayResult(day, 100, win);
    }

    function history(uint24 latest, uint24 gap, uint128 bank, uint128 carry, uint128 stop,
        uint8 mode, uint256 entropy, uint8 pattern) external {
        PlayerCoinflipState storage s = playerState[3];
        s.claimableStored = bank;
        s.autoRebuyCarry = carry;
        s.lastClaim = latest - gap;
        s.autoRebuyStartDay = s.lastClaim;
        s.autoRebuyEnabled = mode != 0;
        s.autoRebuyUnlimited = mode == 2;
        s.autoRebuyStop = stop;
        flipsClaimableDay = latest;
        requestedDailyIdx = latest;
        uint24 first = gap > 90 ? latest - 89 : latest - gap + 1;
        for (uint24 d = first; d <= latest; ++d) {
            uint256 bits = uint256(keccak256(abi.encode(entropy, d)));
            _setFlipStake(d, 3, pattern == 0 ? uint32(bits) : type(uint32).max);
            bool win = pattern == 0 ? bits & 1 != 0 : pattern == 1
                || (pattern == 2 && d != latest) || (pattern == 3 && d % 2 == 0)
                || (pattern >= 5 && d != uint256(first) + pattern - 5);
            _storeDayResult(d, pattern == 0 ? uint16(50 + (bits >> 32) % 107) : 156, win);
        }
        _setFlipStake(latest + 1, 3, 7000);
    }

    function seed(uint24 latest, uint128 bank, uint128 carry, uint32 nextStake) external {
        playerState[3].claimableStored = bank;
        playerState[3].autoRebuyCarry = carry;
        playerState[3].lastClaim = latest;
        flipsClaimableDay = latest;
        requestedDailyIdx = latest;
        _setFlipStake(latest + 1, 3, nextStake);
    }
}

contract GnrusFlipTicketsTest is DeployProtocol {
    GnrusTicketHost internal host;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 3 days);
        vm.etch(address(game), type(GnrusTicketHost).runtimeCode);
        host = GnrusTicketHost(payable(address(game)));
        vm.mockCall(ContractAddresses.CRAPS,
            abi.encodeWithSignature("minerMaintenancePending_g11976()"), abi.encode(false));
    }

    function _seed(uint24 next, uint8 mode, uint128 bank, uint128 carry, uint32 nextStake)
        internal returns (uint24 day)
    {
        day = host.prime(next, mode);
        bytes memory code = address(coinflip).code;
        vm.etch(address(coinflip), type(GnrusFlipSeeder).runtimeCode);
        GnrusFlipSeeder(address(coinflip)).seed(day - 1, bank, carry, nextStake);
        vm.etch(address(coinflip), code);
    }

    function test_earlyTurboDeclaredAtRequestBuysClosingLevel() public {
        _seed(1, 1, 3000, 5000, 7000);
        host.request();
        assertEq(host.committedEntries(1), 3200);
        assertEq(coin.balanceOfWithClaimable(ContractAddresses.GNRUS), 0);
        (bool enabled,, uint256 carry,) = coinflip.coinflipAutoRebuyInfo(ContractAddresses.GNRUS);
        assertTrue(enabled);
        assertEq(carry, 0);
        assertFalse(host.redemptionOpen(), "turbo request closes the redemption window after buying");
    }

    function test_walletGiftsAndBackingAreFullySpent() public {
        uint24 day = _seed(4, 0, 3000, 5000, 7000);
        vm.prank(address(game));
        coin.mintForGame_g152734(ContractAddresses.GNRUS, 2000);
        host.request();
        assertEq(host.committedEntries(4), 4000, "wallet gifts increase the purchase quantity");
        assertEq(coin.balanceOf(ContractAddresses.GNRUS), 0);
        assertEq(coinflip.previewClaimCoinflips(ContractAddresses.GNRUS), 0);
        (bool enabled,, uint256 carry,) = coinflip.coinflipAutoRebuyInfo(ContractAddresses.GNRUS);
        assertTrue(enabled);
        assertEq(carry, 0, "wallet and backing both spent");
        vm.etch(address(coinflip), type(GnrusFlipSeeder).runtimeCode);
        assertEq(GnrusFlipSeeder(address(coinflip)).stake(day), 7000, "committed direct stake is untouched");
    }

    function test_pendingLossIsSettledBeforeSizingCashOut() public {
        uint24 day = _seed(4, 0, 3000, 5000, 7000);
        bytes memory code = address(coinflip).code;
        vm.etch(address(coinflip), type(GnrusFlipSeeder).runtimeCode);
        GnrusFlipSeeder(address(coinflip)).pendingResult(day - 1, false);
        vm.etch(address(coinflip), code);
        host.request();
        assertEq(host.committedEntries(4), 1200, "lost carry cannot fund tickets");
        assertEq(coin.balanceOf(ContractAddresses.GNRUS), 0);
        vm.etch(address(coinflip), type(GnrusFlipSeeder).runtimeCode);
        assertEq(GnrusFlipSeeder(address(coinflip)).stake(day), 7000);
    }

    function test_lastPurchaseLevelsUseClosingLevel() public {
        uint24[8] memory levels = [uint24(1), 4, 5, 10, 15, 95, 100, 101];
        uint256 clean = vm.snapshotState();
        for (uint256 i; i < levels.length; ++i) {
            assertTrue(vm.revertToState(clean));
            clean = vm.snapshotState();
            _seed(levels[i], 0, 10000, 0, 0);
            host.request();
            assertEq(host.committedEntries(levels[i]), 4000);
            assertEq(host.committedEntries(levels[i] + 1), 0);
        }
    }

    function test_emptyAndDustBalancesDoNotBlockRequest() public {
        uint256 clean = vm.snapshotState();
        for (uint128 amount; amount < 3; ++amount) {
            assertTrue(vm.revertToState(clean));
            clean = vm.snapshotState();
            _seed(4, 0, amount, 0, 1000);
            host.request();
            assertEq(host.committedEntries(4), 0);
            assertEq(coinflip.previewClaimCoinflips(ContractAddresses.GNRUS), amount);
        }
    }

    function test_roundingLeavesOnlyUnspendableDust() public {
        _seed(4, 0, 10001, 0, 0);
        host.request();
        assertEq(host.committedEntries(4), 4000);
        assertEq(coinflip.previewClaimCoinflips(ContractAddresses.GNRUS), 1);
    }

    function test_ordinaryPurchaseDayDoesNotWithdrawOrBuy() public {
        _seed(4, 2, 3000, 5000, 7000);
        host.request();
        assertEq(host.committedEntries(4), 0);
        assertEq(coinflip.previewClaimCoinflips(ContractAddresses.GNRUS), 3000);
        (, , uint256 carry,) = coinflip.coinflipAutoRebuyInfo(ContractAddresses.GNRUS);
        assertEq(carry, 5000);
    }

    function test_retryDoesNotPurchaseAgain() public {
        _seed(4, 0, 10000, 0, 7000);
        host.request();
        vm.prank(address(game));
        coin.mintForGame_g152734(ContractAddresses.GNRUS, 2000);
        vm.warp(block.timestamp + 20 hours);
        vm.prank(ContractAddresses.ADMIN);
        game.retryRng();
        assertEq(host.committedEntries(4), 4000);
        assertEq(coin.balanceOf(ContractAddresses.GNRUS), 2000, "retry cannot spend newly arrived FLIP");
    }

    function test_jackpotPhaseRequestDoesNotBuy() public {
        _seed(4, 0, 3000, 5000, 7000);
        host.jackpotRequest();
        host.request();
        assertEq(coin.balanceOfWithClaimable(ContractAddresses.GNRUS), 3000);
        (,, uint256 carry,) = coinflip.coinflipAutoRebuyInfo(ContractAddresses.GNRUS);
        assertEq(carry, 5000);
    }

    function test_inconsistentBelowTargetLatchReverts() public {
        _seed(4, 0, 3000, 5000, 7000);
        host.pool(0);
        vm.expectRevert(abi.encodeWithSignature("E()"));
        host.request();
        assertEq(host.committedEntries(4), 0);
        (,, uint256 carry,) = coinflip.coinflipAutoRebuyInfo(ContractAddresses.GNRUS);
        assertEq(carry, 5000);
    }

    function test_snapDustSkipsWithoutBlockingRequest() public {
        _seed(4, 0, 30, 0, 7000);
        host.snap(4);
        host.request();
        assertEq(host.committedEntries(4), 0);
        assertEq(coin.balanceOfWithClaimable(ContractAddresses.GNRUS), 30);
    }

    function test_playersCannotCallMintWorker() public {
        _seed(4, 0, 10000, 0, 0);
        vm.expectRevert(abi.encodeWithSignature("OnlyDelegatecall()"));
        (bool ok, bytes memory reason) = ContractAddresses.GAME_MINT_MODULE.call(
            abi.encodeWithSignature("redeemGnrusFlip()"));
        // expectRevert changes the low-level return to success.
        ok; reason;
        (ok,) = address(game).call(abi.encodeWithSignature("redeemGnrusFlip()"));
        assertFalse(ok, "Game exposes no player route to the worker");
    }

    function testFuzz_roundUpCostNeverExceedsAvailable(uint64 available) public {
        _seed(4, 0, available, 0, 0);
        host.request();
        uint256 quantity = uint256(available) * 400 / 1000;
        if (quantity > type(uint32).max) quantity = type(uint32).max;
        uint256 cost = (quantity * 250 + 99) / 100;
        assertLe(cost, available);
        if (host.committedEntries(4) != 0) {
            assertEq(host.committedEntries(4), quantity);
            assertEq(coin.balanceOfWithClaimable(ContractAddresses.GNRUS), available - cost);
        }
    }
    function test_plainTransferBuysAtNextClosingRequest() public {
        _seed(4, 0, 0, 0, 0);
        vm.prank(address(game));
        coin.mintForGame_g152734(address(this), 10000);
        coin.transfer(ContractAddresses.GNRUS, 10000);
        host.request();
        assertEq(host.committedEntries(4), 4000);
        assertEq(coin.balanceOf(ContractAddresses.GNRUS), 0);
    }

    function test_walletFundedRequestStillSettlesBeforeSizing() public {
        uint24 day = _seed(4, 0, 0, 10000, 0);
        bytes memory code = address(coinflip).code;
        vm.etch(address(coinflip), type(GnrusFlipSeeder).runtimeCode);
        GnrusFlipSeeder(address(coinflip)).pendingResult(day - 1, true);
        vm.etch(address(coinflip), code);
        vm.prank(address(game));
        coin.mintForGame_g152734(ContractAddresses.GNRUS, 50000);
        host.request();
        assertGt(host.committedEntries(4), 0);
        vm.etch(address(coinflip), type(GnrusFlipSeeder).runtimeCode);
        assertEq(GnrusFlipSeeder(address(coinflip)).cursor(), day - 1,
            "zero deposit settles before combined wallet/backing sizing");
    }

    function test_closedWindowStillSettlesPendingLoss() public {
        uint24 day = _seed(4, 0, 0, 5000, 7000);
        bytes memory code = address(coinflip).code;
        vm.etch(address(coinflip), type(GnrusFlipSeeder).runtimeCode);
        GnrusFlipSeeder(address(coinflip)).pendingResult(day - 1, false);
        vm.etch(address(coinflip), code);
        host.pool(0);
        host.request();
        assertEq(host.committedEntries(4), 0);
        (,,uint256 carry,) = coinflip.coinflipAutoRebuyInfo(ContractAddresses.GNRUS);
        assertEq(carry, 0);
        vm.etch(address(coinflip), type(GnrusFlipSeeder).runtimeCode);
        assertEq(GnrusFlipSeeder(address(coinflip)).cursor(), day - 1);
        assertEq(GnrusFlipSeeder(address(coinflip)).stake(day), 7000);
    }

    function test_dustStillSettlesAndScoresAtRequest() public {
        uint24 day = _seed(10, 0, 0, 1, 7000);
        bytes memory code = address(coinflip).code;
        vm.etch(address(coinflip), type(GnrusFlipSeeder).runtimeCode);
        GnrusFlipSeeder(address(coinflip)).pendingResult(day - 1, true);
        vm.etch(address(coinflip), code);
        uint256 clean = vm.snapshotState();
        vm.recordLogs();
        vm.prank(address(game));
        coinflip.playCoinflip(3, 0);
        bytes32 oldSealScore = _scoreEvent();
        assertTrue(vm.revertToState(clean));
        vm.recordLogs();
        host.request();
        assertEq(_scoreEvent(), oldSealScore, "same closing-bracket credit before BAF resolution");
        assertEq(host.committedEntries(10), 0, "two FLIP cannot buy a scaled entry");
        vm.etch(address(coinflip), type(GnrusFlipSeeder).runtimeCode);
        assertEq(GnrusFlipSeeder(address(coinflip)).cursor(), day - 1);
    }

    function _scoreEvent() private returns (bytes32 digest) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(jackpots) && logs[i].topics[0]
                == keccak256("BafFlipRecorded(uint32,uint24,uint256,uint256)"))
                return keccak256(abi.encode(logs[i].topics, logs[i].data));
        }
        revert("missing BAF score");
    }

    function testFuzz_phaseEndingWindowOpens(uint16 levelSeed, uint64 target, uint64 excess) public {
        uint24 closingLevel = uint24(bound(levelSeed, 1, 1000));
        _seed(closingLevel, 0, 0, 10000, 0);
        host.targetAndPool(target, excess);
        (bool locked, uint256 pool_, uint256 threshold) = host.boundaryState();
        assertFalse(locked);
        assertGt(pool_, threshold);
        host.request();
        assertEq(host.committedEntries(closingLevel), 4000);
    }

    function test_unlimitedStopSentinelAndExpiryEdges() public {
        uint24[5] memory gaps = [uint24(0), 1, 89, 90, 91];
        uint256 clean = vm.snapshotState();
        for (uint256 i; i < gaps.length; ++i) {
            assertTrue(vm.revertToState(clean));
            clean = vm.snapshotState();
            bytes memory code = address(coinflip).code;
            vm.etch(address(coinflip), type(GnrusFlipSeeder).runtimeCode);
            GnrusFlipSeeder(address(coinflip)).history(1432, gaps[i], type(uint128).max,
                type(uint128).max, 1, 2, 0, 1);
            vm.etch(address(coinflip), code);
            uint256 preview = coinflip.previewFlipBackingById(3);
            vm.prank(address(coin));
            assertEq(coinflip.consumeFlipBacking(ContractAddresses.GNRUS, preview), preview);
            assertEq(coinflip.previewFlipBackingById(3), 0);
        }
    }

    function test_publicBurnRoutesCannotSpendGnrus() public {
        _seed(5, 0, 3000, 5000, 0);
        vm.expectRevert();
        coin.burnCoin_g27673(ContractAddresses.GNRUS, 2000);
        vm.expectRevert();
        coin.burnCoinForCraps_g292454(ContractAddresses.GNRUS, 3, 2000 << 8);
        vm.expectRevert(abi.encodeWithSignature("NotApproved()"));
        coin.decimatorBurn(3, 2000, 0);
        vm.expectRevert();
        coinflip.consumeFlipBacking(ContractAddresses.GNRUS, 2000);
        assertEq(coinflip.previewFlipBackingById(3), 8000);
    }

    function testFuzz_walletPlusBackingFundsRoundedBurn(uint64 walletSeed, uint64 bankSeed, uint64 carrySeed) public {
        uint256 wallet = bound(walletSeed, 0, 20_000_000_000);
        uint128 bank = uint128(bound(bankSeed, 0, 20_000_000_000));
        uint128 carry = uint128(bound(carrySeed, 0, 20_000_000_000));
        uint256 available = wallet + bank + carry;
        vm.assume(available >= 1000);
        _seed(4, 0, bank, carry, 7000);
        if (wallet != 0) {
            vm.prank(address(game));
            coin.mintForGame_g152734(address(this), wallet);
            coin.transfer(ContractAddresses.GNRUS, wallet);
        }
        uint256 quantity = available * 400 / 1000;
        if (quantity > type(uint32).max) quantity = type(uint32).max;
        uint256 cost = (quantity * 250 + 99) / 100;
        assertLe(cost, available);
        uint256 walletUsed = wallet < cost ? wallet : cost;
        uint256 supply = coin.totalSupply();
        host.request();
        assertEq(host.committedEntries(4), quantity);
        assertEq(coin.balanceOf(ContractAddresses.GNRUS), wallet - walletUsed);
        assertEq(coin.totalSupply(), supply - walletUsed);
        assertEq(coinflip.previewFlipBackingById(3), uint256(bank) + carry - (cost - walletUsed));
    }

    function testFuzz_previewExactlyMatchesConsumption(uint128 bank, uint128 carry, uint128 stop,
        uint16 gapSeed, uint8 modeSeed, uint256 entropy) public {
        // Both expired and full windows, ring/page boundaries, capped carry, loss sentinels,
        // every possible reward byte, disabled rebuy and finite/unlimited take-profit.
        uint24 latest = 1432;
        uint24 gap = uint24(bound(gapSeed, 0, 180));
        uint8 mode = modeSeed % 3;
        bytes memory code = address(coinflip).code;
        vm.etch(address(coinflip), type(GnrusFlipSeeder).runtimeCode);
        GnrusFlipSeeder(address(coinflip)).history(latest, gap, bank, carry, stop, mode, entropy, 0);
        vm.etch(address(coinflip), code);
        uint256 preview = coinflip.previewFlipBackingById(3);
        uint256 supply = coin.totalSupply();
        vm.prank(address(coin));
        uint256 consumed = coinflip.consumeFlipBacking(ContractAddresses.GNRUS, preview);
        assertEq(consumed, preview);
        assertEq(coinflip.previewFlipBackingById(3), 0);
        assertEq(coin.totalSupply(), supply);
        assertEq(coin.balanceOf(ContractAddresses.GNRUS), 0);
        (bool enabled,,,) = coinflip.coinflipAutoRebuyInfo(ContractAddresses.GNRUS);
        assertEq(enabled, mode != 0);
        vm.etch(address(coinflip), type(GnrusFlipSeeder).runtimeCode);
        assertEq(GnrusFlipSeeder(address(coinflip)).stake(latest + 1), 7000);
    }

}
