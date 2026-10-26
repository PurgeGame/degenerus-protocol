// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm} from "forge-std/Vm.sol";
import {ForkDeployProtocol} from "./ForkDeployProtocol.sol";
import {ForkPins} from "./ForkPins.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {DegenerusVaultShare} from "../../contracts/DegenerusVault.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

/// @dev Etched over the Game for one call to seed a backed claimable credit (the caller deals the
///      backing ETH); the real runtime is restored straight after.
contract ForkClaimableSeeder is DegenerusGameStorage {
    function credit(uint32 id, uint256 amount) external {
        _creditClaimable(id, amount);
        claimablePool += uint128(amount);
    }
}

/// @title ForkSteth -- every protocol stETH leg against the REAL Lido stETH (v3, contract version 4).
/// @notice Lido moves SHARES: transfer(x) moves floor(x * shares / pooled) shares and submit(x) mints
///         floor(x * shares / pooled), so a recipient's balanceOf can rise by up to 2 wei less than
///         the nominal amount at the pinned share rate (~1.2463 ETH per share), and a sender's falls
///         by at most the nominal amount. The mock the rest of the suite uses trades 1:1 and never
///         rounds. These tests run the real protocol paths through the real token and assert:
///           - nothing reverts or bricks because of share rounding,
///           - every recipient gets >= nominal - STETH_ROUNDING (2 wei) per transfer,
///           - the game stays solvent (SolvencyObligations: ETH + stETH >= the obligation set) up to
///             the measured Lido rounding: every Lido.submit the game makes mints up to 2 wei less
///             stETH than the ETH it sends, and nothing in the protocol makes that good, so a game
///             holding exactly its obligations is left up to 2 wei per stake short of them (until
///             the next positive rebase). The budget is asserted per counted submit,
///           - a positive rebase accrues to the game as yield over unchanged obligations.
contract ForkStethTest is ForkDeployProtocol {
    /// @dev The per-transfer rounding bound at the pinned share rate: a recipient's balance rises
    ///      by > x - pooled/shares - 1 = x - 2.25 wei.
    uint256 internal constant STETH_ROUNDING = 2;

    bytes32 private constant LIDO_SUBMITTED = keccak256("Submitted(address,uint256,address)");
    bytes32 private constant WINNINGS_CLAIMED = keccak256("WinningsClaimed(uint32,uint256,uint128)");
    bytes32 private constant AFKING_STETH_FUNDED = keccak256("AfkingStethFunded(uint32,uint256,uint256)");

    address private driver = makeAddr("driver");
    address private alice = makeAddr("alice");
    uint256 private autoStaked;
    uint256 private autoStakes;
    /// @dev Every Lido.submit the game made (automatic and manual): the solvency rounding budget.
    uint256 private lidoSubmits;
    uint256 private worstDeficit;

    /// @dev The vault burns DGVE through this contract (CREATOR holds the initial DGVE supply).
    receive() external payable {}

    function setUp() public {
        _forkAndDeploy();
        vm.deal(driver, 1_000_000 ether);
    }

    // ------------------------------------------------------------------ fixtures

    /// @dev Real play to level 3. Every phase transition auto-stakes the game's ETH above its
    ///      claimable reserve through Lido.submit; those Submitted events are tallied.
    function _runningGame() private {
        _play(3, 40);
        assertGe(game.currentLvl(), 3, "fixture: the game must be mid-run");
    }

    function _play(uint24 target, uint256 maxDays) private {
        vm.recordLogs();
        _playUntilLevel(driver, target, maxDays, 60 ether);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == ForkPins.STETH && logs[i].topics[0] == LIDO_SUBMITTED
                && address(uint160(uint256(logs[i].topics[1]))) == address(game)) {
                (uint256 amount,) = abi.decode(logs[i].data, (uint256, address));
                autoStaked += amount;
                ++autoStakes;
                ++lidoSubmits;
            }
        }
    }

    function _adminStake(uint256 amount) private {
        vm.prank(ContractAddresses.OWNER_GOVERNANCE);
        game.adminStakeEthForStEth(amount);
        ++lidoSubmits;
    }

    /// @dev SolvencyObligations with the Lido rounding budget made explicit: the backing may trail
    ///      the obligations only by what the game's own submits lost to share rounding.
    function _assertSolvent(string memory where) private {
        uint256 b = _backing();
        uint256 o = _obligations();
        uint256 deficit = o > b ? o - b : 0;
        if (deficit > worstDeficit) worstDeficit = deficit;
        emit log_named_string("solvency check", where);
        emit log_named_uint("  backing (ETH + real stETH)", b);
        emit log_named_uint("  obligations", o);
        emit log_named_uint("  strict deficit (wei)", deficit);
        assertLe(deficit, STETH_ROUNDING * lidoSubmits, where);
    }

    function _seedClaimable(uint32 id, uint256 amount) private {
        bytes memory real = address(game).code;
        vm.etch(address(game), type(ForkClaimableSeeder).runtimeCode);
        ForkClaimableSeeder(address(game)).credit(id, amount);
        vm.etch(address(game), real);
        vm.deal(address(game), address(game).balance + amount);
    }

    /// @dev The ETH the Game keeps for native VRF funding at the default 150k callback gas limit
    ///      (the same product as the Game's VRF_NATIVE_TARGET).
    function _vrfNativeTarget() private pure returns (uint256) {
        uint256 premium = 100 + ContractAddresses.VRF_NATIVE_PREMIUM;
        uint256 stress = 300_000 * 1 gwei * premium / 100;
        uint256 lowWater = 2 * ContractAddresses.VRF_LANE_MAX_GAS_PRICE * 350_000 * premium / 100 + 5 * 12 * stress;
        return lowWater + 2 * 400 * stress;
    }

    /// @dev What the vault owner may stake right now (the game's own Insolvent guard).
    function _stakeable() private view returns (uint256) {
        uint256 settleable = game.claimableWinningsOf(ContractAddresses.VAULT)
            + game.claimableWinningsOf(ContractAddresses.SDGNRS) + game.redemptionReserve();
        uint256 pool = game.claimablePoolView();
        uint256 reserve = (pool > settleable ? pool - settleable : 0) + _vrfNativeTarget();
        uint256 bal = address(game).balance;
        return bal > reserve ? bal - reserve : 0;
    }

    function _received(address who) private view returns (uint256) {
        return who.balance + lido.balanceOf(who);
    }

    // ------------------------------------------------------------------ staking

    /// @notice The advance chain's automatic stake (phase transition) and the vault owner's manual
    ///         stake both go through the real Lido.submit; the minted stETH is within the rounding
    ///         bound of the ETH staked, and the game stays solvent across both.
    function test_autoAndAdminStakeSubmitToRealLido() public {
        _runningGame();
        assertGt(autoStakes, 0, "a phase transition auto-staked through Lido");
        assertGe(lido.balanceOf(address(game)) + STETH_ROUNDING * autoStakes, autoStaked, "auto-stake minted");
        _assertSolvent("after auto-stake");

        // The auto-stake leaves ETH only for ETH-settled claims. Vault claimable settles in stETH,
        // so a backed Vault credit is ETH the owner may stake.
        _seedClaimable(game.walletIdOf_g3120(ContractAddresses.VAULT), 10 ether);
        uint256 amount = _stakeable() / 2;
        assertGt(amount, 1 ether, "fixture: free ETH to stake");
        uint256 eth0 = address(game).balance;
        uint256 st0 = lido.balanceOf(address(game));
        uint256 sh0 = lido.sharesOf(address(game));
        uint256 expectedShares = lido.getSharesByPooledEth(amount);
        uint256 backing0 = _backing();
        _adminStake(amount);
        uint256 minted = lido.balanceOf(address(game)) - st0;
        assertEq(eth0 - address(game).balance, amount, "ETH left for Lido");
        assertEq(lido.sharesOf(address(game)) - sh0, expectedShares, "Lido minted floor(x * shares / pooled)");
        assertLe(minted, amount);
        assertGe(minted + STETH_ROUNDING, amount, "minted within the rounding bound");
        emit log_named_uint("admin stake rounding loss (wei)", amount - minted);
        assertEq(minted, lido.getPooledEthByShares(lido.sharesOf(address(game))) - lido.getPooledEthByShares(sh0),
            "the loss is exactly Lido's share flooring");
        assertEq(backing0 - _backing(), amount - minted, "the stake costs the backing exactly that loss");
        assertLe(amount - minted, STETH_ROUNDING, "a stake costs the backing at most the rounding");
        _assertSolvent("after admin stake");

        // The guard still binds against the real balance: the player-claim reserve cannot be staked.
        uint256 over = _stakeable() + 1;
        vm.prank(ContractAddresses.OWNER_GOVERNANCE);
        vm.expectRevert(bytes4(keccak256("Insolvent()")));
        game.adminStakeEthForStEth(over);
    }

    /// @notice The owner's ETH-for-stETH swap pays real stETH: the owner receives within the
    ///         rounding bound, the game never gives up more stETH than nominal, and its backing
    ///         does not fall.
    function test_adminSwapPaysRealSteth() public {
        _runningGame();
        uint256 amount = lido.balanceOf(address(game)) / 3;
        assertGt(amount, 1 ether, "fixture: game holds stETH");
        address owner = ContractAddresses.CREATOR;
        vm.deal(ContractAddresses.OWNER_GOVERNANCE, amount);
        uint256 ownerSt = lido.balanceOf(owner);
        uint256 gameSt = lido.balanceOf(address(game));
        uint256 backing0 = _backing();
        vm.prank(ContractAddresses.OWNER_GOVERNANCE);
        admin.swapGameEthForStEth{value: amount}(owner);
        uint256 got = lido.balanceOf(owner) - ownerSt;
        uint256 gave = gameSt - lido.balanceOf(address(game));
        emit log_named_uint("swap: recipient shortfall (wei)", amount - got);
        assertGe(got + STETH_ROUNDING, amount, "owner received within the rounding bound");
        assertLe(gave, amount, "the game never sends more than nominal");
        assertGe(_backing(), backing0, "a swap never costs the game backing");
        _assertSolvent("after swap");

        // Swapping the game's ENTIRE stETH balance (balanceOf-reported) still succeeds.
        uint256 all = lido.balanceOf(address(game));
        vm.deal(ContractAddresses.OWNER_GOVERNANCE, all);
        vm.prank(ContractAddresses.OWNER_GOVERNANCE);
        admin.swapGameEthForStEth{value: all}(owner);
        assertLe(lido.balanceOf(address(game)), STETH_ROUNDING, "only rounding dust left");
    }

    // ------------------------------------------------------------------ rebase

    /// @notice A positive Lido rebase (the consensus-layer balance leg of an oracle report, replayed
    ///         through Lido's Accounting-gated processClStateUpdate) raises the game's stETH balance
    ///         at an unchanged share count; the gain shows up 1:1 as yield surplus over unchanged
    ///         obligations, and the game keeps playing on the rebased token.
    function test_positiveRebaseAccruesToTheGameAsYield() public {
        _runningGame();
        uint256 shares = lido.sharesOf(address(game));
        uint256 st0 = lido.balanceOf(address(game));
        uint256 yield0 = game.yieldPoolView();
        uint256 obligations0 = _obligations();
        uint256 backing0 = _backing();
        // The submits' rounding left the backing this far under the obligations (yield0 is then 0).
        uint256 deficit0 = obligations0 > backing0 ? obligations0 - backing0 : 0;
        emit log_named_uint("pre-rebase strict deficit (wei)", deficit0);
        assertGt(st0, 1 ether, "fixture: game holds stETH");

        uint256 pooled = lido.getTotalPooledEther();
        // +0.5% on the validators' balance. The replayed report also re-bases Lido's
        // deposited-since-report term, so the net pooled-ether rise is measured, not assumed.
        _lidoPositiveRebase(pooled / 200);
        uint256 pooled1 = lido.getTotalPooledEther();
        assertGt(pooled1, pooled + pooled / 1000, "pooled ether rose (> +0.1%)");
        emit log_named_uint("Lido pooled ether rise (wei)", pooled1 - pooled);
        assertEq(lido.sharesOf(address(game)), shares, "share count untouched");

        uint256 st1 = lido.balanceOf(address(game));
        assertEq(st1, lido.getPooledEthByShares(shares), "balance is shares at the new rate");
        assertApproxEqAbs(st1 - st0, st0 * (pooled1 - pooled) / pooled, 2, "the game's stETH rose with the share rate");
        emit log_named_uint("rebase gain to the game (wei)", st1 - st0);
        assertEq(_obligations(), obligations0, "obligations unchanged");
        // The gain first repays the rounding deficit; the rest is yield surplus, to the wei.
        assertEq(game.yieldPoolView() - yield0 + deficit0, st1 - st0, "the gain is yield surplus");
        assertGe(_backing(), _obligations(), "a positive rebase restores strict solvency");
        _assertSolvent("after rebase");

        // The game keeps running on the rebased token.
        _play(game.currentLvl() + 1, 20);
        _assertSolvent("after playing on the rebased token");
    }

    // ------------------------------------------------------------------ game over

    /// @notice The terminal path on real stETH: the game ends holding mostly stETH, every claim
    ///         pays (ETH first, then the real stETH fallback) within the rounding bound, the final
    ///         sweep's _sendStethFirst legs pay the vault, sDGNRS and GNRUS, and the downstream
    ///         stETH holders (vault DGVE burn, DGNRS burn, sDGNRS burn) pass real stETH on without
    ///         reverting.
    function test_gameOverClaimsSweepAndHolderBurnsOnRealSteth() public {
        _runningGame();
        // Give alice sDGNRS (the Reward pool) for the post-game-over sDGNRS burn, and a DGNRS holder.
        _giveWalletId(alice);
        uint256 share = sdgnrs.totalSupply() / 50;
        vm.prank(address(game));
        sdgnrs.transferFromPool_g106128(sDGNRS.Pool.Reward, alice, share);
        address holder = makeAddr("dgnrsHolder");
        _dgnrsFromVault(holder, dgnrs.balanceOf(ContractAddresses.VAULT) / 10);

        // Hold as much of the backing in stETH as the guard allows, then end the game.
        // A backed Vault credit settles in stETH, so its ETH is stakeable: the game ends ETH-short for it.
        _seedClaimable(game.walletIdOf_g3120(ContractAddresses.VAULT), 10 ether);
        if (_stakeable() != 0) _adminStake(_stakeable());
        _driveToGameOver();
        _assertSolvent("at game over");
        emit log_named_uint("game ETH at game over", address(game).balance);
        emit log_named_uint("game stETH at game over", lido.balanceOf(address(game)));

        // Claims: drain the game's ETH with the first claims so later ones need the stETH leg.
        address[5] memory who = [driver, address(this), ContractAddresses.CREATOR, alice, ContractAddresses.VAULT];
        uint256 stethLegs;
        uint256 worst;
        for (uint256 i; i < who.length; ++i) {
            if (i > 0 && who[i] == who[i - 1]) continue;
            if (game.claimableWinningsOf(who[i]) <= 1 && game.afkingFundingOf(who[i]) == 0) continue;
            uint256 before = _received(who[i]);
            uint256 stBefore = lido.balanceOf(who[i]);
            vm.recordLogs();
            vm.prank(who[i]);
            game.claimClaimable(0);
            uint256 payout = _claimedPayout(vm.getRecordedLogs());
            uint256 got = _received(who[i]) - before;
            if (lido.balanceOf(who[i]) > stBefore) ++stethLegs;
            assertLe(got, payout, "never more than the payout");
            assertGe(got + STETH_ROUNDING, payout, "claim paid within the rounding bound");
            if (payout - got > worst) worst = payout - got;
            _assertSolvent("after a claim");
        }
        emit log_named_uint("claims that used the stETH fallback", stethLegs);
        assertGt(stethLegs, 0, "an ETH-short claim paid through the real stETH fallback");
        emit log_named_uint("worst claim shortfall (wei)", worst);

        // The final sweep, 30 days on: everything leaves the game, stETH first.
        uint256 v0 = _received(ContractAddresses.VAULT);
        uint256 s0 = _received(ContractAddresses.SDGNRS);
        uint256 g0 = _received(ContractAddresses.GNRUS);
        uint256 funds = address(game).balance + lido.balanceOf(address(game));
        uint256 stethBefore = lido.balanceOf(address(game));
        assertGt(stethBefore, 0, "fixture: the sweep has stETH to move");
        vm.warp(vm.getBlockTimestamp() + 30 days + 1);
        _crank(40);
        assertEq(address(game).balance, 0, "sweep left ETH");
        uint256 dust = lido.balanceOf(address(game));
        emit log_named_uint("stETH dust stranded in the game after the sweep (wei)", dust);
        assertLe(dust, 3 * STETH_ROUNDING, "sweep left more than rounding dust");
        uint256 paid = (_received(ContractAddresses.VAULT) - v0) + (_received(ContractAddresses.SDGNRS) - s0)
            + (_received(ContractAddresses.GNRUS) - g0);
        assertLe(paid, funds);
        assertGe(paid + 3 * STETH_ROUNDING, funds, "the three legs received everything within rounding");

        // Downstream holders pass real stETH on.
        _burnDgve();
        _burnDgnrs(holder);
        _burnSdgnrs();
    }

    function _claimedPayout(Vm.Log[] memory logs) private view returns (uint256 payout) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == WINNINGS_CLAIMED) {
                (payout,) = abi.decode(logs[i].data, (uint256, uint128));
                return payout;
            }
        }
        revert("no WinningsClaimed");
    }

    /// @dev The vault's DGVE burn pays ETH then real stETH. This contract (CREATOR) holds the DGVE
    ///      supply; half of it is burned.
    function _burnDgve() private {
        DegenerusVaultShare dgve = DegenerusVaultShare(vm.computeCreateAddress(address(vault), 2));
        uint256 amount = dgve.balanceOf(address(this)) / 2;
        assertGt(amount, 0, "fixture: CREATOR holds DGVE");
        assertGt(lido.balanceOf(ContractAddresses.VAULT), 0, "fixture: the vault holds swept stETH");
        (uint256 previewEth, uint256 previewSt) = vault.previewEth(amount);
        uint256 before = _received(address(this));
        (uint256 ethOut, uint256 stOut) = vault.burnEth(amount);
        uint256 got = _received(address(this)) - before;
        emit log_named_uint("DGVE burn stETH out", stOut);
        assertEq(ethOut + stOut, previewEth + previewSt, "burn pays its preview");
        assertGt(stOut, 0, "the DGVE burn used the stETH leg");
        assertGe(got + STETH_ROUNDING, ethOut + stOut, "DGVE burn paid within the rounding bound");
    }

    /// @dev DGNRS.burn after game over: sDGNRS pays DGNRS (stETH leg), DGNRS forwards the same
    ///      nominal stethOut. The pass-through must work although DGNRS's balanceOf may read
    ///      2 wei short of what it was sent (shares, not balances, are what move).
    function _burnDgnrs(address holder) private {
        uint256 amount = dgnrs.balanceOf(holder);
        uint256 before = _received(holder);
        vm.prank(holder);
        (uint256 ethOut, uint256 stOut,) = dgnrs.burn(amount);
        uint256 got = _received(holder) - before;
        emit log_named_uint("DGNRS burn stETH out", stOut);
        assertGe(got + 2 * STETH_ROUNDING, ethOut + stOut, "DGNRS burn paid within two transfers' rounding");
        assertLe(lido.balanceOf(address(dgnrs)), STETH_ROUNDING, "DGNRS keeps at most rounding dust");
    }

    /// @dev A direct post-game-over sDGNRS burn: ETH first, then real stETH.
    function _burnSdgnrs() private {
        uint256 amount = sdgnrs.balanceOf(alice);
        uint256 before = _received(alice);
        vm.prank(alice);
        (uint256 ethOut, uint256 stOut,) = sdgnrs.burn(amount);
        uint256 got = _received(alice) - before;
        emit log_named_uint("sDGNRS burn stETH out", stOut);
        assertGe(got + STETH_ROUNDING, ethOut + stOut, "sDGNRS burn paid within the rounding bound");
    }

    // ------------------------------------------------------------------ redemption

    /// @notice A live sDGNRS redemption against a Game whose backing is partly REAL stETH (the
    ///         vault owner staked the sDGNRS-settleable ETH): the batch closes inside the real daily
    ///         request, settles on the real word through mineFlip, and the claim legs pay the
    ///         beneficiary. The live close moves no value: the whole pull stays in the Game as its
    ///         redemption reserve, and the live legs settle from that reserve, never touching
    ///         ETH custody or stETH. Nothing reverts and the game stays solvent.
    function test_liveRedemptionSettlesThroughRealStethLegs() public {
        _runningGame();
        _giveWalletId(alice);
        uint256 share = sdgnrs.totalSupply() / 50;
        vm.prank(address(game));
        sdgnrs.transferFromPool_g106128(sDGNRS.Pool.Reward, alice, share);

        // sDGNRS holds a backed game claimable (its redemption reserve source). The vault owner
        // stakes everything the guard allows — sDGNRS's claimable is stETH-settleable — and the
        // driver takes its winnings in ETH, so the game is left ETH-short for the close.
        _seedClaimable(game.walletIdOf_g3120(ContractAddresses.SDGNRS), 500 ether);
        if (game.claimableWinningsOf(driver) > 1) {
            vm.prank(driver);
            game.claimClaimable(0);
        }
        _adminStake(_stakeable());
        assertGt(lido.balanceOf(address(game)), 0, "fixture: the game holds real stETH backing");
        _assertSolvent("before the burn");

        uint32 batch;
        (batch,,,) = sdgnrs.redemptionBatchState();
        vm.prank(alice);
        sdgnrs.burn(share);
        (uint128 tokens,) = sdgnrs.pendingRedemptions(game.walletIdOf_g3120(alice), batch);
        assertGt(tokens, 0, "alice joined the open batch");

        uint256 sdSt0 = lido.balanceOf(ContractAddresses.SDGNRS);
        uint256 sdEth0 = ContractAddresses.SDGNRS.balance;
        uint256 gameEth0 = address(game).balance;
        uint256 gameSt0 = lido.balanceOf(address(game));
        // Next day: the daily request closes the batch (the whole pull stays reserved in the Game).
        vm.warp(vm.getBlockTimestamp() + 1 days);
        for (uint256 i; i < 64 && !game.rngLocked(); ++i) {
            vm.prank(keeper);
            game.mineRun(0);
        }
        assertTrue(game.rngLocked(), "fixture: daily request");
        uint256 reserved = sdgnrs.pendingRedemptionEthValue();
        uint256 sdEth = ContractAddresses.SDGNRS.balance;
        uint256 gameReserve = game.redemptionReserve();
        emit log_named_uint("game ETH before the close", gameEth0);
        emit log_named_uint("batch maximum reserved by sDGNRS", reserved);
        emit log_named_uint("Game redemption reserve after the close", gameReserve);
        assertGt(reserved, 0, "the batch closed with a reserve");
        assertEq(lido.balanceOf(ContractAddresses.SDGNRS), sdSt0, "the live close moves no stETH");
        assertGe(lido.balanceOf(address(game)) + STETH_ROUNDING, gameSt0, "the Game keeps its stETH backing");
        assertEq(sdEth, sdEth0, "the close sends no ETH to sDGNRS");
        assertEq(gameReserve, reserved, "the whole batch maximum is the Game reserve");

        uint256 aliceClaimable0 = game.claimableWinningsOf(alice);
        _crank(400);
        (uint128 left,) = sdgnrs.pendingRedemptions(game.walletIdOf_g3120(alice), batch);
        assertEq(left, 0, "the claim settled through the live legs");
        assertGt(game.claimableWinningsOf(alice), aliceClaimable0 + 1, "the direct half reached alice's claimable");
        assertEq(lido.balanceOf(ContractAddresses.SDGNRS), sdSt0, "live settlement moves no stETH");
        emit log_named_uint("Game reserve after settlement", game.redemptionReserve());
        assertLt(game.redemptionReserve(), gameReserve, "the live legs drew on the Game reserve");
        _assertSolvent("after redemption settlement");
    }

    // ------------------------------------------------------------------ afking

    /// @notice A subscriber who funds AFKing with stETH: subscribe's first buy pulls the shortfall
    ///         with the real Lido transferSharesFrom (shares rounded UP so the game receives at
    ///         least the shortfall); any rounding excess is credited back to the funder.
    function test_afkingSubscriptionPullsRealStethShares() public {
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _crank(200);
        assertFalse(game.rngLocked(), "fixture: day settled, subscription window open");

        address player = makeAddr("afkPlayer");
        uint256 seat = _grantSeat(player);
        _giveWalletId(player);
        _realSteth(player, 2 ether);
        vm.prank(player);
        lido.approve(address(game), type(uint256).max);

        uint256 playerSt = lido.balanceOf(player);
        uint256 playerShares = lido.sharesOf(player);
        uint256 gameSt = lido.balanceOf(address(game));
        vm.prank(player);
        game.subscribe(0, true, 1, seat);
        // A new run checkpoints today and buys from the next day's subscriber pass.
        vm.warp(vm.getBlockTimestamp() + 1 days);
        vm.recordLogs();
        _crank(200);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 shortfall;
        uint256 received;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == AFKING_STETH_FUNDED) {
                (shortfall, received) = abi.decode(logs[i].data, (uint256, uint256));
            }
        }
        assertGt(shortfall, 0, "the first buy was funded by the stETH pull");
        uint256 sharesMoved = playerShares - lido.sharesOf(player);
        assertEq(lido.balanceOf(address(game)) - gameSt, received, "game balance delta = credited receipt");
        assertGe(received, shortfall, "the game received at least the shortfall");
        assertLe(received - shortfall, 2, "rounding excess is at most a share's worth");
        assertEq(game.afkingFundingOf(player), received - shortfall, "excess credited back to the funder");
        assertGe(playerSt - lido.balanceOf(player) + 1, received, "player paid what the game received");
        emit log_named_uint("afking pull: shares moved", sharesMoved);
        emit log_named_uint("afking pull: shortfall", shortfall);
        emit log_named_uint("afking pull: received", received);
    }
}
