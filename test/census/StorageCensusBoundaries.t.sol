// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;


import {StorageCensus} from "./StorageCensus.sol";
import {console} from "forge-std/console.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {TicketQueueStorage} from "../fuzz/helpers/TicketQueueStorage.sol";
import {GameFunding} from "../helpers/GameFunding.sol";

/// @title CensusBoundaryBase -- shared driving for the boundary campaigns
/// @dev Each campaign plays its approach with the census OFF (`censusOn = false`: calls still run,
///      nothing is logged), then switches it on for the boundary window under its own scenario
///      name. Pool seeding and level jumps (vm.store) are never census transactions.
abstract contract CensusBoundaryBase is StorageCensus {
    uint256 internal constant N = 16;
    uint256 internal constant NO_BUY = type(uint256).max;
    address[] internal cast;
    DegenerusGameLens internal lens;

    function _baseSetUp() internal {
        _deployProtocol();
        lens = new DegenerusGameLens();
        mockVRF.fundSubscription(1, 1_000 ether);
        for (uint256 i; i < N; ++i) {
            address p = address(uint160(0xB0DA000 + i));
            cast.push(p);
            vm.deal(p, 50_000 ether);
        }
        _censusRegisterProtocol();
        censusOn = false;
    }

    function _on(string memory scenario) internal {
        censusOn = true;
        _censusBegin(scenario);
    }

    function _off() internal {
        _censusEnd();
        censusOn = false;
    }

    function _warpDay(uint24 d, uint256 secs) internal {
        vm.warp(uint256(d - 1) * 1 days + GameTimeLib.JACKPOT_RESET_TIME + secs);
    }

    function _today() internal view returns (uint24) {
        return game.currentDayView();
    }

    function _act(string memory label, uint256 i, address to, uint256 value, bytes memory data)
        internal
        returns (bool ok, bytes memory ret)
    {
        address p = cast[i];
        if (p.balance < value + 1 ether) vm.deal(p, p.balance + value + 100 ether);
        return _ctx(label, false, p, to, value, data);
    }

    function _buy(uint256 i, uint256 tickets, uint256 box) internal {
        uint256 price = game.mintPrice();
        _act("purchase", i, address(game), tickets * price + box, abi.encodeCall(game.purchase,
            (uint32(0), tickets * 400, box == 0 ? 0 : BoxOrderLib.boCustomFloor(box), bytes32(0), MintPaymentKind.DirectEth, false)));
    }

    /// @dev One game day: open, buy `1/divisor` of the gap to the level target (divisor 0: no
    ///      purchases beyond one small box), crank at the open, +6h and +14h.
    function _day(uint256 divisor) internal {
        uint24 d = _today() + 1;
        _warpDay(d, 10 minutes);
        _cMineAll(3000, d);
        if (divisor == NO_BUY) {
            // Idle day: cranks only.
        } else if (divisor != 0) {
            uint256 next = game.nextPrizePoolView();
            uint256 target = game.prizePoolTargetView();
            uint256 need = next > target ? 0.5 ether : (target - next) * 10 / (9 * divisor) + 1 ether;
            if (need > 60 ether) need = 60 ether;
            uint256 per = need / game.mintPrice() / 4 + 1;
            for (uint256 j; j < 4; ++j) _buy((uint256(d) * 3 + j * 5) % N, per, j == 0 ? 0.3 ether : 0);
        } else {
            _buy(uint256(d) % N, 1, 0.05 ether);
        }
        _warpDay(d, 6 hours);
        _cMineAll(3000, d + 1_000);
        _warpDay(d, 14 hours);
        _cMineAll(3000, d + 2_000);
    }

    function _playToLevel(uint24 lvl, uint256 maxDays, uint256 divisor) internal {
        for (uint256 k; k < maxDays && game.level() < lvl && !game.gameOver(); ++k) _day(divisor);
    }

    function _seedNextPrizePool(uint256 targetNext) internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(GameSlots.PRIZE_POOLS_PACKED)));
        if (uint128(packed) >= targetNext) return;
        vm.store(address(game), bytes32(GameSlots.PRIZE_POOLS_PACKED),
            bytes32((packed & ~uint256(type(uint128).max)) | targetNext));
    }

    function _seedFuturePrizePool(uint256 targetFuture) internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(GameSlots.PRIZE_POOLS_PACKED)));
        if (packed >> 128 >= targetFuture) return;
        vm.store(address(game), bytes32(GameSlots.PRIZE_POOLS_PACKED), bytes32(uint256(uint128(packed)) | (targetFuture << 128)));
    }

    /// @dev Teleport a live game (level >= 2) to `lvl` (WwxrpIncinerator.t.sol's `_jumpLevel`): level,
    ///      the two trait-buffer level stamps, and retire every skipped level's queues.
    function _jumpLevel(uint24 lvl) internal {
        uint256 s0 = uint256(vm.load(address(game), bytes32(0)));
        s0 = (s0 & ~(uint256(0xFFFFFF) << 96)) | (uint256(lvl) << 96);
        vm.store(address(game), bytes32(0), bytes32(s0));
        uint256 s5 = uint256(vm.load(address(game), bytes32(uint256(5))));
        uint48 stamps = uint48(uint256(lvl) << ((lvl & 1) * 24) | uint256(lvl + 1) << (((lvl + 1) & 1) * 24));
        vm.store(address(game), bytes32(uint256(5)), bytes32((s5 & ~(uint256(type(uint48).max) << 80)) | (uint256(stamps) << 80)));
        TicketQueueStorage.retireCompleted(address(game), lvl + 1);
    }

    function _flipFloat(uint256 i, uint256 amount) internal {
        vm.prank(address(game));
        coin.mintForGame(cast[i], amount);
    }

    function _fundLender() internal {
        vm.deal(address(sdgnrs), address(sdgnrs).balance + 100 ether);
        GameFunding.credit(2, 500 ether);
    }

    /// @dev Borrow for player i due at `due`, when the lens quotes an eligible loan.
    function _borrow(uint256 i, uint24 due) internal returns (bool ok) {
        uint32 id = game.walletIdOf_g3120(cast[i]);
        if (id == 0) return false;
        DegenerusGameLens.LoanQuote memory q;
        try lens.previewBorrow(address(game), id, due, type(uint256).max) returns (DegenerusGameLens.LoanQuote memory r) {
            q = r;
        } catch {}
        if (!q.eligible || q.principal < 0.05 ether) return false;
        (ok,) = _act("borrow", i, address(game), 0, abi.encodeCall(game.borrow, (id, due, type(uint256).max, uint256(0))));
    }
}

/// @title StorageCensusBoundaries -- boundary campaigns on the default (post-Degenesis) deployment
contract StorageCensusBoundariesTest is CensusBoundaryBase {
    function setUp() public {
        _baseSetUp();
    }

    // ------------------------------------------------------------------ century, WWXRP x99, loans at x00

    /// @notice x97 -> x101 with the level-99 WWXRP incinerator, the x99 decimator window, the x00
    ///         BAF and century consolidation. Approach: organic play to level 2, then the
    ///         WwxrpIncinerator teleport to 97 (GNRUS pickCharity mocked: its own level counter
    ///         rejects the jump, so GNRUS per-level writes are absent here). Pools are seeded each
    ///         day like the incinerator suite, so ticket volume is light.
    function testCenturyRollover() public {
        vm.pauseGasMetering();
        _playToLevel(2, 60, 1);
        assertGe(game.level(), 2, "bootstrap");
        vm.mockCall(ContractAddresses.GNRUS, abi.encodeWithSignature("pickCharity(uint24)"), abi.encode());
        _jumpLevel(97);
        vm.deal(address(game), address(game).balance + 5_000 ether);
        for (uint256 i; i < N; ++i) {
            _flipFloat(i, 500_000);
            vm.prank(address(game));
            wwxrp.mintPrize(cast[i], 5_000);
        }
        _on("century");
        for (uint256 day; day < 80 && game.level() <= 101 && !game.gameOver(); ++day) {
            uint24 lvl = game.level();
            _seedNextPrizePool(49.9 ether + day * 10 ether);
            _seedFuturePrizePool(200 ether);
            uint24 d = _today() + 1;
            _warpDay(d, 10 minutes);
            _cMineAll(3000, d);
            for (uint256 j; j < 6; ++j) {
                uint256 i = (uint256(d) * 5 + j * 3) % N;
                _buy(i, 4 + j, j % 2 == 0 ? 0.2 ether : 0);
                _act("depositCoinflip", i, address(coinflip), 0, abi.encodeCall(coinflip.depositCoinflip, (uint32(0), uint256(1_000))));
                _act("wwxrpEnter", i, address(wwxrp), 0, abi.encodeCall(wwxrp.enter, (uint32(0), uint256(50 + j * 25))));
                if (game.decWindow()) {
                    _act("decimatorBurn", i, address(coin), 0, abi.encodeCall(coin.decimatorBurn, (uint32(0), uint256(2_000), uint32(0))));
                }
            }
            if (lvl == 99 || lvl == 100) {
                _act("purchaseWhalePass", d % N, address(game), 9 ether,
                    abi.encodeCall(game.purchaseWhalePass, (uint32(0), uint256(2), bytes32(0))));
            }
            _warpDay(d, 6 hours);
            _cMineAll(3000, d + 1_000);
            _warpDay(d, 14 hours);
            _cMineAll(3000, d + 2_000);
        }
        _off();
        assertGt(game.level(), 100, "crossed the century");
    }

    // ------------------------------------------------------------------ loan horizon

    /// @notice Loans at the 100-level horizon and short loans crossing their due level (seizure or
    ///         auto-repay inside mineFlip), then re-borrowing by the same accounts.
    function testLoanHorizon() public {
        vm.pauseGasMetering();
        _playToLevel(2, 60, 1);
        // Collateral: whale passes queue far-future tickets for 100 levels.
        for (uint256 i; i < 8; ++i) {
            _act("purchaseWhalePass", i, address(game), 10 ether,
                abi.encodeCall(game.purchaseWhalePass, (uint32(0), uint256(2), bytes32(0))));
        }
        _fundLender();
        _day(2);
        _on("loanHorizon");
        uint24 lvl = game.level();
        uint24 cl = lvl + 1; // outside the jackpot phase the active ticket level is level + 1
        for (uint256 i; i < 4; ++i) _borrow(i, cl + 98 - uint24(i)); // the horizon edge
        for (uint256 i = 4; i < 8; ++i) _borrow(i, lvl + 2 + uint24(i - 4)); // due within a few levels
        _playToLevel(lvl + 7, 60, 2);
        // Second generation: the short borrowers borrow again (their loan words were cleared).
        _fundLender();
        for (uint256 i = 4; i < 8; ++i) _borrow(i, game.level() + 2 + uint24(i - 4));
        _playToLevel(game.level() + 6, 60, 2);
        // Repay what is still open.
        for (uint256 i; i < 8; ++i) {
            uint32 id = game.walletIdOf_g3120(cast[i]);
            DegenerusGameLens.LoanInfo memory info = lens.loanOf(address(game), id);
            if (info.principal != 0 && info.dueLevel > game.level()) {
                _act("repay", i, address(game), info.owed + 0.01 ether, abi.encodeCall(game.repay, (id)));
            }
        }
        _off();
    }

    function _purchaseInfo() internal view returns (uint24, bool, bool, bool, uint256) {
        return game.purchaseInfo();
    }

    // ------------------------------------------------------------------ BAF bracket, fire and skip

    /// @notice Level 9's last purchase day (the BAF draw is armed) across into level 10 and 11,
    ///         once with every VRF word odd (BAF fires) and once with every word even (BAF skipped,
    ///         consolation claims), from the same snapshot.
    function testBafBracket() public {
        vm.pauseGasMetering();
        for (uint256 i; i < N; ++i) _flipFloat(i, 2_000_000);
        for (uint256 k; k < 120 && !game.gameOver(); ++k) {
            (uint24 pl,, bool lastDay,,) = _purchaseInfo();
            if (pl == 9 && lastDay) break;
            // Coinflip activity before the bracket builds BAF scores (claims record them).
            uint256 i = k % N;
            _act("depositCoinflip", i, address(coinflip), 0, abi.encodeCall(coinflip.depositCoinflip, (uint32(0), uint256(5_000))));
            _act("claimCoinflips", (k + 7) % N, address(coinflip), 0,
                abi.encodeCall(coinflip.claimCoinflips, (uint32(0), type(uint256).max)));
            _day(1);
        }
        uint256 snap = vm.snapshotState();
        _bafWindow("bafFire", 1);
        vm.revertToState(snap);
        _bafWindow("bafSkip", 2);
    }

    function _bafWindow(string memory scenario, uint8 parity) internal {
        censusWordParity = parity;
        _on(scenario);
        // Direct deposits after the latch enter the weighted BAF draw.
        for (uint256 i; i < N; ++i) {
            _act("depositCoinflip", i, address(coinflip), 0, abi.encodeCall(coinflip.depositCoinflip, (uint32(0), uint256(1_000 + i * 100))));
        }
        uint256 guard;
        while (game.level() < 12 && guard++ < 40 && !game.gameOver()) {
            _day(2);
            uint24 lvl = game.level();
            for (uint256 j; j < 6; ++j) {
                uint256 i = (guard * 5 + j) % N;
                _act("claimCoinflips", i, address(coinflip), 0,
                    abi.encodeCall(coinflip.claimCoinflips, (uint32(0), type(uint256).max)));
                if (lvl >= 10) {
                    _act("claimBafConsolation", i, address(jackpots), 0, abi.encodeCall(jackpots.claimBafConsolation, (uint32(0), uint24(10))));
                }
            }
        }
        _off();
        censusWordParity = 0;
    }

    // ------------------------------------------------------------------ coinflip 90-day window

    /// @notice Stakes made on days 1-5 at level 0, left unclaimed past the 90-day window (half the
    ///         cast claims at day ~45 for contrast), then claimed and re-deposited. Level 0 has a
    ///         250-day purchase timeout, so the quiet stretch is legal.
    function testCoinflipClaimExpiry() public {
        vm.pauseGasMetering();
        for (uint256 i; i < N; ++i) _flipFloat(i, 200_000);
        _on("coinflipExpiry");
        for (uint256 k; k < 106; ++k) {
            if (k < 5 || k >= 100) {
                for (uint256 i; i < N; ++i) {
                    _act("depositCoinflip", i, address(coinflip), 0, abi.encodeCall(coinflip.depositCoinflip, (uint32(0), uint256(1_000 + k))));
                }
            }
            if (k == 45 || k >= 100) {
                for (uint256 i; i < N; i += k == 45 ? 2 : 1) {
                    _act("claimCoinflips", i, address(coinflip), 0,
                        abi.encodeCall(coinflip.claimCoinflips, (uint32(0), type(uint256).max)));
                }
            }
            _day(0);
        }
        _off();
    }

    // ------------------------------------------------------------------ craps 64-day ring

    /// @notice 75 days at level 0 with daily craps play and future-day purchases, so the 64-day bet
    ///         and membership banks wrap.
    function testCrapsRingWrap() public {
        vm.pauseGasMetering();
        uint32 board = 3 | (3 << 12) | (1 << 15);
        _on("crapsRing");
        for (uint256 k; k < 75; ++k) {
            uint24 d = _today() + 1;
            _warpDay(d, 5 minutes);
            _cMineAll(3000, d);
            for (uint256 j; j < 4; ++j) {
                uint256 i = (k * 4 + j) % N;
                if (coin.balanceOf(cast[i]) < 600_000) _flipFloat(i, 2_000_000);
                if (crapsBattle.daySeatNumberOf(d, cast[i]) != 0) continue;
                if (j < 2) {
                    _act("crapsEnterBonusDay", i, address(crapsBattle), 0,
                        abi.encodeWithSignature("enterBonusDay(uint32,uint32,uint16)", uint32(0), board, uint16(1)));
                } else {
                    _act("crapsEnterWindow", i, address(crapsBattle), 0, abi.encodeWithSignature(
                        "enterBonusBattle(uint32,uint256,uint32,uint16)", uint32(0), uint256(j), board, uint16(1)));
                }
            }
            uint256 b = (k * 7 + 1) % N;
            if (coin.balanceOf(cast[b]) < 600_000) _flipFloat(b, 2_000_000);
            _act("crapsBuyFutureDays", b, address(crapsBattle), 0, abi.encodeWithSignature(
                "buyFutureCrapsDays(uint32,uint24,uint8,bool,uint32)", uint32(0), d + 2 + uint24(k % 25), uint8(2), false, board));
            _buy(k % N, 1, 0);
            _warpDay(d, 6 hours);
            _cMineAll(3000, d + 1_000);
            _warpDay(d, 14 hours);
            _cMineAll(3000, d + 2_000);
        }
        _off();
    }

    // ------------------------------------------------------------------ game over (VRF alive) and sweep

    /// @notice Live level-3 game with open loans, subscriptions, coinflip stakes and an sDGNRS
    ///         batch; purchases stop, the 30-day purchase deadline fires, the terminal path runs with
    ///         VRF answering, then the 30-day final sweep, then post-game-over claims and burns.
    function testGameOverVrfAlive() public {
        vm.pauseGasMetering();
        _playToLevel(3, 80, 1);
        for (uint256 i; i < 6; ++i) {
            _act("purchaseWhalePass", i, address(game), 10 ether,
                abi.encodeCall(game.purchaseWhalePass, (uint32(0), uint256(2), bytes32(0))));
        }
        _fundLender();
        _day(3);
        for (uint256 i; i < 4; ++i) _borrow(i, game.level() + 3 + uint24(i));
        for (uint256 i; i < N; ++i) {
            _flipFloat(i, 100_000);
            _act("depositCoinflip", i, address(coinflip), 0, abi.encodeCall(coinflip.depositCoinflip, (uint32(0), uint256(2_000))));
        }
        for (uint256 i = 8; i < 12; ++i) {
            vm.prank(address(game));
            sdgnrs.transferFromPool(sDGNRS.Pool.Reward, cast[i], 20_000 * 1e12);
            _act("sdgnrsBurn", i, address(sdgnrs), 0, abi.encodeCall(sdgnrs.burn, (uint256(5_000 * 1e12))));
        }
        // Idle days alone never end this game: the protocol's own AFKing subscriptions (Vault,
        // sDGNRS) keep buying and the levels keep moving. The ending used here is the deadman: no
        // one cranks for 31 days, then the next cranks find liveness fired and run the terminal
        // path with VRF answering every request.
        _on("gameOver");
        _day(NO_BUY);
        uint24 quiet = _today() + 32;
        _warpDay(quiet, 1 hours);
        uint256 rounds;
        for (; rounds < 40 && !game.gameOver(); ++rounds) {
            _cMineAll(3000, quiet + rounds);
            if (!game.gameOver()) vm.warp(vm.getBlockTimestamp() + 2 hours);
        }
        console.log(string.concat("CENSUSNOTE|gameOver|crankRoundsToGameOver|", vm.toString(rounds),
            "|level|", vm.toString(uint256(game.level())), "|gameOver|", game.gameOver() ? "1" : "0"));
        // Final sweep window.
        uint24 d = _today() + 31;
        _warpDay(d, 1 hours);
        _cMineAll(3000, d);
        _warpDay(d + 1, 1 hours);
        _cMineAll(3000, d + 1);
        for (uint256 i; i < N; ++i) {
            if (game.claimableWinningsOf(cast[i]) > 1) {
                _act("claimWinnings", i, address(game), 0, abi.encodeWithSignature("claimWinnings(uint32)", uint32(0)));
            }
            if (sdgnrs.balanceOf(cast[i]) > 1e12) {
                _act("sdgnrsBurnDeterministic", i, address(sdgnrs), 0, abi.encodeCall(sdgnrs.burn, (sdgnrs.balanceOf(cast[i]) / 2)));
            }
            _act("claimCoinflips", i, address(coinflip), 0, abi.encodeCall(coinflip.claimCoinflips, (uint32(0), type(uint256).max)));
        }
        _off();
        require(game.gameOver(), "game over latched");
    }
}

/// @title StorageCensusDegenesisBoundary -- Degenesis close -> main launch on the day-1 deployment
contract StorageCensusDegenesisBoundaryTest is CensusBoundaryBase {
    function _deployTimestamp() internal pure override returns (uint256) {
        return DEPLOY_TS_DEGENESIS;
    }

    function setUp() public {
        _baseSetUp();
    }

    /// @notice Sale days 1..6 play with the census off; the census covers sale day 7, the launch day,
    ///         the settlement of the last cohorts until all seven close, and three ordinary days.
    function testDegenesisCloseToLaunch() public {
        vm.pauseGasMetering();
        _warpDay(1, 30 minutes);
        _cMineAll(3000, 1);
        for (uint256 i; i < N; ++i) _buy(i, 3, 0.5 ether); // earns Degenesis credit
        _cMineAll(3000, 2);
        for (uint256 c = 1; c <= 7; ++c) {
            if (c == 7) _on("degenesisClose");
            _saleDay(c);
        }
        uint24 d = GameTimeLib.MAIN_LAUNCH_DAY;
        for (uint256 k; k < 10; ++k) {
            _warpDay(d, 20 minutes);
            _cMineAll(3000, d);
            for (uint256 j; j < 4; ++j) _buy((uint256(d) + j * 4) % N, 2, j == 0 ? 0.2 ether : 0);
            _warpDay(d, 13 hours);
            _cMineAll(3000, d + 500);
            if (_closed() == 7 && k >= 3) break;
            ++d;
        }
        console.log(string.concat("CENSUSNOTE|degenesisClose|closedCohorts|", vm.toString(uint256(_closed()))));
        _off();
    }

    function _closed() internal view returns (uint8) {
        return uint8(uint256(vm.load(address(game), bytes32(GameSlots.DEGENESIS_CLOSED))) >> (GameSlots.DEGENESIS_CLOSED_OFFSET * 8));
    }

    function _saleDay(uint256 c) internal {
        uint24 d = uint24(c + 1);
        _warpDay(d, 5 minutes);
        _cMineAll(3000, 100 + c);
        for (uint256 k; k < 8; ++k) {
            uint256 i = (c * 5 + k * 3) % N;
            uint256 amount = (100 + uint256(keccak256(abi.encode(c, k))) % 4900) * 0.0001 ether;
            uint256 credit = game.degenesisCreditOf(cast[i]);
            if (credit < amount) {
                uint256 spend = ((amount - credit) * 4 + 0.001 ether - 1) / 0.001 ether * 0.001 ether;
                if (spend < 0.01 ether) spend = 0.01 ether;
                _act("purchase", i, address(game), spend, abi.encodeCall(game.purchase,
                    (uint32(0), 0, BoxOrderLib.boCustom(spend), bytes32(0), MintPaymentKind.DirectEth, false)));
            }
            _act("buyDegenesisBox", i, address(game), amount, abi.encodeCall(game.buyDegenesisBox, (uint32(0), amount)));
        }
        _warpDay(d, 13 hours);
        _cMineAll(3000, 300 + c);
    }
}
