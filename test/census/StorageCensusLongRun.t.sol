// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {StorageCensus} from "./StorageCensus.sol";
import {console} from "forge-std/console.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {OwnerTargetCall} from "../helpers/OwnerTargetCall.sol";

interface ICensusShare {
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address who) external view returns (uint256);
}

/// @title StorageCensusLongRun -- deterministic long scenario: Degenesis week, then normal play
/// @notice A fixed cast plays a scripted daily mix on the real deployment while every top-level
///         call is censused (test/census/StorageCensus.sol). The run stops at TARGET_LEVEL or
///         MAX_PLAY_DAYS after launch. Feature calls that revert are logged (CENSUSTX ...|reverted)
///         and counted, never fatal: the census measures what the protocol does, not the script.
/// @dev Seeded setup that is NOT part of the census (direct calls outside `_ctx`): player ETH,
///      a FLIP float for the cast (coin.mintForGame as the Game), a small sDGNRS float for
///      burners/voters (sDGNRS.transferFromPool as the Game), DGVE shares from the creator, two
///      GNRUS charity slots, VRF subscription LINK and the loan lender's backing.
contract StorageCensusLongRunTest is StorageCensus {
    uint256 internal constant PLAYERS = 30;
    uint24 internal constant TARGET_LEVEL = 31;
    uint24 internal constant MAX_PLAY_DAYS = 260;

    address[] internal cast;
    DegenerusGameLens internal lens;
    uint256 internal salt = 0xCE5505;
    mapping(uint256 => mapping(uint24 => bool)) internal votedAt; // player => level
    mapping(uint256 => bool) internal governanceDeposited;
    uint256 internal deityHolder; // index + 1
    uint32 internal deityId;

    function _deployTimestamp() internal pure override returns (uint256) {
        return DEPLOY_TS_DEGENESIS;
    }

    function setUp() public {
        _deployProtocol();
        lens = new DegenerusGameLens();
        mockVRF.fundSubscription(1, 1_000 ether);
        for (uint256 i; i < PLAYERS; ++i) {
            address p = address(uint160(0xCA57000 + i));
            cast.push(p);
            vm.deal(p, 20_000 ether);
        }
        // Two charity slots so GNRUS votes have somewhere to go.
        vm.startPrank(ContractAddresses.OWNER_GOVERNANCE);
        gnrus.setCharity(3, address(0xC4A1));
        gnrus.setCharity(4, address(0xC4A2));
        vm.stopPrank();
    }

    function testLongRunCensus() public {
        vm.pauseGasMetering();
        _censusBegin("longrun");
        _playDeployDay();
        for (uint256 c = 1; c <= 7; ++c) _degenesisDay(c);
        _seedFloats();
        uint24 launch = GameTimeLib.MAIN_LAUNCH_DAY;
        for (uint24 d = launch; d < launch + MAX_PLAY_DAYS && game.level() < TARGET_LEVEL && !game.gameOver(); ++d) {
            _playDay(d);
        }
        _censusEnd();
        console.log(string.concat("CENSUSNOTE|longrun|mineReverts|", vm.toString(censusMineReverts)));
        assertGt(censusCreates, 0);
    }

    // ------------------------------------------------------------------------------- calendar

    function _warpDay(uint24 d, uint256 secs) internal {
        vm.warp(uint256(d - 1) * 1 days + GameTimeLib.JACKPOT_RESET_TIME + secs);
    }

    function _rand(uint256 a, uint256 b) internal view returns (uint256) {
        return uint256(keccak256(abi.encode(salt, a, b)));
    }

    function _crank(uint256 tag) internal {
        _cMineAll(3000, _rand(tag, block.timestamp));
    }

    // ------------------------------------------------------------------------------- Degenesis

    /// @dev Deploy day (index 1): affiliate codes, then every player's first purchase (with a
    ///      referral code) earns Degenesis credit.
    function _playDeployDay() internal {
        _crank(1);
        for (uint256 i; i < 3; ++i) {
            _act("createAffiliateCode", i, address(affiliate), 0,
                abi.encodeCall(affiliate.createAffiliateCode, (_code(i), uint8(5 + i * 5))));
        }
        for (uint256 i; i < PLAYERS; ++i) {
            uint256 box = 0.2 ether + (_rand(i, 1) % 20) * 0.05 ether;
            uint256 price = game.mintPrice();
            uint256 tickets = 2 + _rand(i, 2) % 6;
            _act("purchase", i, address(game), tickets * price + box, abi.encodeCall(game.purchase,
                (uint32(0), tickets * 400, BoxOrderLib.boCustomFloor(box), i < 3 ? bytes32(0) : _code(i % 3),
                 MintPaymentKind.DirectEth, false)));
        }
        _crank(2);
    }

    function _code(uint256 i) internal pure returns (bytes32) {
        return bytes32(abi.encodePacked("CENSUS-AFF-", bytes1(uint8(0x30 + i))));
    }

    /// @dev Degenesis day c (index c + 1): buyers place one or two orders against their credit,
    ///      topping credit up with a real lootbox purchase when short.
    function _degenesisDay(uint256 c) internal {
        uint24 d = uint24(c + 1);
        _warpDay(d, 5 minutes);
        _crank(100 + c);
        for (uint256 k; k < 8; ++k) {
            uint256 i = (c * 7 + k * 3) % PLAYERS;
            uint256 amount = (100 + _rand(c, k) % 4900) * 0.0001 ether;
            uint256 credit = game.degenesisCreditOf(cast[i]);
            if (credit < amount) {
                uint256 spend = ((amount - credit) * 4 + 0.001 ether - 1) / 0.001 ether * 0.001 ether;
                if (spend < 0.01 ether) spend = 0.01 ether;
                _act("purchase", i, address(game), spend, abi.encodeCall(game.purchase,
                    (uint32(0), 0, BoxOrderLib.boCustom(spend), bytes32(0), MintPaymentKind.DirectEth, false)));
            }
            _act("buyDegenesisBox", i, address(game), amount, abi.encodeCall(game.buyDegenesisBox, (uint32(0), amount)));
            if (k == 3) {
                _warpDay(d, 7 hours);
                _crank(200 + c);
            }
        }
        _warpDay(d, 13 hours);
        _crank(300 + c);
    }

    /// @dev FLIP, sDGNRS and DGVE floats for features whose organic sources are slow or rare.
    function _seedFloats() internal {
        ICensusShare dgve = ICensusShare(vault.dgve());
        for (uint256 i; i < PLAYERS; ++i) {
            vm.prank(address(game));
            coin.mintForGame(cast[i], 200_000);
            if (i % 3 == 0) {
                vm.prank(address(game));
                sdgnrs.transferFromPool(sDGNRS.Pool.Reward, cast[i], 50_000 * 1e12);
            }
            if (i % 5 == 0) dgve.transfer(cast[i], 1e9 * 1e18 / 1000);
            vm.prank(address(game));
            wwxrp.mintPrize(cast[i], 2_000);
        }
        // Lender backing: sDGNRS (wallet 2) lends against far-future tickets when it holds claimable.
        vm.deal(address(sdgnrs), 600 ether);
        vm.prank(address(sdgnrs));
        game.creditRedemptionDirect{value: 500 ether}(2, 500 ether);
    }

    // ------------------------------------------------------------------------------- one day

    function _playDay(uint24 d) internal {
        _warpDay(d, 10 minutes);
        _crank(d);
        _purchases(d);
        _craps(d);
        _afking(d);
        _flipActions(d);
        _sidebets(d);
        _passesAndBoons(d);
        _tokenActions(d);
        _warpDay(d, 6 hours);
        _crank(d + 7_000);
        _lateActions(d);
        _closeCustomBattle();
        _warpDay(d, 14 hours);
        _crank(d + 14_000);
    }

    /// @dev Tickets sized to the gap to the level target (so levels move every few days), plus
    ///      lootboxes for a rotating third of the cast.
    function _purchases(uint24 d) internal {
        uint256 next = game.nextPrizePoolView();
        uint256 target = game.prizePoolTargetView();
        // About a third of the gap a day: a level's purchase phase lasts three to four days.
        uint256 need = next > target ? 0.5 ether : (target - next) * 10 / 27 + 1 ether;
        if (need > 40 ether) need = 40 ether;
        uint256 price = game.mintPrice();
        uint256 perBuyer = need / price / 6 + 1;
        for (uint256 j; j < 10; ++j) {
            uint256 i = (uint256(d) * 7 + j * 3) % PLAYERS;
            uint256 tickets = j < 6 ? perBuyer : 1 + _rand(d, j) % 3;
            uint256 box = j % 3 == 0 ? 0.1 ether + (_rand(d, j + 50) % 10) * 0.1 ether : 0;
            _act("purchase", i, address(game), tickets * price + box, abi.encodeCall(game.purchase,
                (uint32(0), tickets * 400, box == 0 ? 0 : BoxOrderLib.boCustomFloor(box), bytes32(0),
                 MintPaymentKind.DirectEth, false)));
        }
        // Spend winnings: claimable-paid tickets for two players.
        for (uint256 j; j < 2; ++j) {
            uint256 i = (uint256(d) * 11 + j * 13) % PLAYERS;
            if (game.claimableWinningsOf(cast[i]) > price * 2) {
                _act("purchaseClaimable", i, address(game), 0, abi.encodeCall(game.purchase,
                    (uint32(0), 400, 0, bytes32(0), MintPaymentKind.Claimable, false)));
            }
        }
    }

    /// @dev Coinflip deposits, claims, auto-rebuy; WWXRP draws and prize claims; BAF consolation.
    function _flipActions(uint24 d) internal {
        for (uint256 j; j < 6; ++j) {
            uint256 i = (uint256(d) * 5 + j * 4) % PLAYERS;
            uint256 amount = 100 + _rand(d, 300 + j) % 5_000;
            _act("depositCoinflip", i, address(coinflip), 0, abi.encodeCall(coinflip.depositCoinflip, (uint32(0), amount)));
        }
        if (d % 3 == 0) {
            for (uint256 j; j < 5; ++j) {
                uint256 i = (uint256(d) + j * 6) % PLAYERS;
                _act("claimCoinflips", i, address(coinflip), 0,
                    abi.encodeCall(coinflip.claimCoinflips, (uint32(0), type(uint256).max)));
            }
        }
        if (d % 10 == 0) {
            uint256 i = (uint256(d) / 10) % PLAYERS;
            _act("setCoinflipAutoRebuy", i, address(coinflip), 0,
                abi.encodeWithSignature("setCoinflipAutoRebuy(uint32,bool,uint256)", uint32(0), d % 20 == 0, uint256(0)));
        }
        // WWXRP: draw entries from claimable/wallet, then claim yesterday's winner if any.
        for (uint256 j; j < 3; ++j) {
            uint256 i = (uint256(d) * 3 + j * 10) % PLAYERS;
            _act("wwxrpEnter", i, address(wwxrp), 0, abi.encodeCall(wwxrp.enter, (uint32(0), uint256(25))));
        }
        (bool found, uint32 idx,) = _findWinner(d - 1);
        if (found) _act("wwxrpClaim", d % PLAYERS, address(wwxrp), 0, abi.encodeCall(wwxrp.claim, (d - 1, idx)));
        if (d % 4 == 0) {
            uint256 i = (uint256(d) / 4) % PLAYERS;
            _act("wwxrpWithdraw", i, address(wwxrp), 0, abi.encodeCall(wwxrp.withdraw, (uint32(0), uint256(0))));
        }
        // BAF consolation after a skipped bracket.
        uint24 lvl = game.level();
        if (lvl >= 10 && lvl % 10 == 0 && d % 2 == 0) {
            for (uint256 j; j < 3; ++j) {
                _act("claimBafConsolation", (uint256(d) + j * 9) % PLAYERS, address(jackpots), 0,
                    abi.encodeCall(jackpots.claimBafConsolation, (uint32(0), lvl)));
            }
        }
    }

    function _findWinner(uint24 day) internal view returns (bool found, uint32 idx, uint32 id) {
        try wwxrp.findWinningEntry(day) returns (bool f, uint32 i, uint32 w) {
            return (f, i, w);
        } catch {}
    }

    /// @dev Degenerette bets, Decimator burns, Parimutuel growth bets.
    function _sidebets(uint24 d) internal {
        for (uint256 j; j < 3; ++j) {
            uint256 i = (uint256(d) * 13 + j * 7) % PLAYERS;
            uint8 symbol = uint8(_rand(d, 400 + j) % 24);
            _act("degeneretteEth", i, address(game), 0.02 ether,
                abi.encodeCall(game.placeDegeneretteBet, (uint32(0), uint8(0), uint128(0.01 ether), uint8(2), symbol)));
        }
        for (uint256 j; j < 2; ++j) {
            uint256 i = (uint256(d) * 17 + j * 5) % PLAYERS;
            _act("degeneretteFlip", i, address(game), 0,
                abi.encodeCall(game.placeDegeneretteBet, (uint32(0), uint8(1), uint128(200), uint8(3), uint8(_rand(d, 450 + j) % 24))));
        }
        if (game.decWindow()) {
            for (uint256 j; j < 5; ++j) {
                uint256 i = (uint256(d) * 3 + j * 6) % PLAYERS;
                _act("decimatorBurn", i, address(coin), 0, abi.encodeCall(coin.decimatorBurn, (uint32(0), uint256(2000), uint32(0))));
            }
        }
        if (game.jackpotPhase() && game.level() != 0) {
            for (uint256 j; j < 4; ++j) {
                uint256 i = (uint256(d) * 19 + j * 7) % PLAYERS;
                _act("parimutuelBet", i, address(parimutuel), 0, abi.encodeCall(parimutuel.placeBet, (uint32(0), j % 2 == 0)));
            }
        }
    }

    /// @dev Whale / lazy / deity passes, deity boons, affiliate DGNRS claims, loans.
    function _passesAndBoons(uint24 d) internal {
        uint24 lvl = game.level();
        if (d % 6 == 0) {
            uint256 i = (uint256(d) / 6) % PLAYERS;
            _act("purchaseWhalePass", i, address(game), 5 ether,
                abi.encodeCall(game.purchaseWhalePass, (uint32(0), uint256(1), bytes32(0))));
        }
        if (d % 6 == 3) {
            uint256 i = (uint256(d) / 6 + 15) % PLAYERS;
            _act("purchaseLazyPass", i, address(game), 4 ether, abi.encodeCall(game.purchaseLazyPass, (uint32(0), bytes32(0))));
        }
        if (deityHolder == 0 && lvl >= 2) {
            uint256 i = 29;
            (bool ok,) = _act("purchaseDeityPass", i, address(game), 30 ether,
                abi.encodeCall(game.purchaseDeityPass, (uint32(0), uint8(9), bytes32(0))));
            if (ok) {
                deityHolder = i + 1;
                deityId = game.walletIdOf(cast[i]);
            }
        }
        if (deityHolder != 0) {
            for (uint8 slot; slot < 3; ++slot) {
                uint32 recipient = game.walletIdOf(cast[(uint256(d) * 3 + slot * 7) % (PLAYERS - 1)]);
                if (recipient == 0) continue;
                _act("issueDeityBoon", deityHolder - 1, address(game), 0,
                    abi.encodeCall(game.issueDeityBoon, (deityId, recipient, slot)));
            }
        }
        if (d % 5 == 0 && lvl > 0) {
            for (uint256 i; i < 3; ++i) {
                _act("claimAffiliateDgnrs", i, address(game), 0, abi.encodeWithSignature("claimAffiliateDgnrs(uint32)", uint32(0)));
            }
        }
        _loans(d, lvl);
    }

    /// @dev Borrow against far-future tickets (whale-pass holders have them), repay half the loans.
    function _loans(uint24 d, uint24 lvl) internal {
        for (uint256 j; j < 2; ++j) {
            uint256 i = (uint256(d) / 2 + j * 15) % PLAYERS;
            uint32 id = game.walletIdOf(cast[i]);
            if (id == 0) continue;
            DegenerusGameLens.LoanInfo memory info = _loanOf(id);
            if (info.principal != 0) {
                if (_rand(d, 600 + j) % 3 != 0 && info.dueLevel > lvl) {
                    _act("repay", i, address(game), info.owed + 0.01 ether, abi.encodeCall(game.repay, (id)));
                }
                continue;
            }
            uint24 due = lvl + 2 + uint24(_rand(d, 610 + j) % 5);
            DegenerusGameLens.LoanQuote memory q;
            try lens.previewBorrow(address(game), id, due, type(uint256).max) returns (DegenerusGameLens.LoanQuote memory r) {
                q = r;
            } catch {}
            if (!q.eligible || q.principal < 0.05 ether) continue;
            _act("borrow", i, address(game), 0, abi.encodeCall(game.borrow, (id, due, type(uint256).max, uint256(0))));
        }
    }

    function _loanOf(uint32 id) internal view returns (DegenerusGameLens.LoanInfo memory info) {
        try lens.loanOf(address(game), id) returns (DegenerusGameLens.LoanInfo memory r) {
            info = r;
        } catch {}
    }

    /// @dev sDGNRS burns, GNRUS votes, Vault share burns, OwnerGovernance positions, winnings claims.
    function _tokenActions(uint24 d) internal {
        uint24 lvl = game.level();
        if (d % 5 == 1) {
            for (uint256 j; j < 3; ++j) {
                uint256 i = ((uint256(d) / 5 + j) * 3) % PLAYERS;
                uint256 bal = sdgnrs.balanceOf(cast[i]);
                if (bal < 2_000 * 1e12) continue;
                _act("sdgnrsBurn", i, address(sdgnrs), 0, abi.encodeCall(sdgnrs.burn, (bal / 10)));
            }
        }
        for (uint256 j; j < 4; ++j) {
            uint256 i = (uint256(d) + j * 3) % PLAYERS;
            if (votedAt[i][lvl] || sdgnrs.balanceOf(cast[i]) < 1e12) continue;
            votedAt[i][lvl] = true;
            uint8 slot = uint8(3 + (i + lvl) % 2);
            (bool ok,) = _act("gnrusVote", i, address(gnrus), 0, abi.encodeCall(gnrus.vote, (slot)));
            // Last level's winner is not votable this level: vote the other charity instead.
            if (!ok) _act("gnrusVote", i, address(gnrus), 0, abi.encodeCall(gnrus.vote, (uint8(7 - slot))));
        }
        ICensusShare dgve = ICensusShare(vault.dgve());
        if (d % 7 == 2) {
            uint256 i = ((uint256(d) / 7) % 6) * 5;
            uint256 bal = dgve.balanceOf(cast[i]);
            if (bal > 0) _act("vaultBurnEth", i, address(vault), 0, abi.encodeCall(vault.burnEth, (bal / 50)));
        }
        if (d % 7 == 5) {
            uint256 i = ((uint256(d) / 7 + 3) % 6) * 5;
            uint256 bal = dgve.balanceOf(cast[i]);
            if (bal > 0) _act("vaultBurnCoin", i, address(vault), 0, abi.encodeCall(vault.burnCoin, (bal / 50)));
        }
        if (d % 3 == 0) _act("vaultDonate", d % PLAYERS, address(vault), 0.05 ether, "");
        // OwnerGovernance: deposit, later withdraw, later deposit again (position churn).
        if (d % 4 == 3) {
            uint256 i = ((uint256(d) / 4) % 3) * 5;
            if (!governanceDeposited[i]) {
                uint256 bal = dgve.balanceOf(cast[i]);
                if (bal > 0) {
                    _act("dgveApprove", i, address(dgve), 0, abi.encodeCall(dgve.approve, (address(ownerGovernance), bal / 2)));
                    (bool ok,) = _act("governanceDeposit", i, address(ownerGovernance), 0,
                        abi.encodeCall(ownerGovernance.deposit, (bal / 2, address(0))));
                    governanceDeposited[i] = ok;
                }
            } else {
                (bool ok,) = _act("governanceWithdraw", i, address(ownerGovernance), 0, abi.encodeCall(ownerGovernance.withdraw, ()));
                if (ok) governanceDeposited[i] = false;
            }
        }
        if (d % 4 == 1) {
            for (uint256 j; j < 4; ++j) {
                uint256 i = (uint256(d) + j * 7) % PLAYERS;
                if (game.claimableWinningsOf(cast[i]) > 0.01 ether) {
                    _act("claimWinnings", i, address(game), 0, abi.encodeWithSignature("claimWinnings(uint32)", uint32(0)));
                }
            }
        }
    }

    /// @dev Afternoon: a second, smaller wave of tickets and boxes (boxes opened mid-day).
    function _lateActions(uint24 d) internal {
        uint256 price = game.mintPrice();
        for (uint256 j; j < 3; ++j) {
            uint256 i = (uint256(d) * 23 + j * 9) % PLAYERS;
            uint256 box = 0.4 ether;
            _act("purchase", i, address(game), price + box, abi.encodeCall(game.purchase,
                (uint32(0), uint256(400), BoxOrderLib.boCustomFloor(box), bytes32(0), MintPaymentKind.DirectEth, false)));
        }
    }

    // ------------------------------------------------------------------------------- craps

    uint32 internal constant BOARD = 3 | (3 << 12) | (1 << 15);
    uint64 internal openCustomSlot;

    /// @dev Day battle, a scheduled window, the jackpot field, future days and banked passes, and a
    ///      weekly custom battle. Runs in the first 20 minutes of the day (period 0 still open).
    function _craps(uint24 d) internal {
        uint24 today = crapsBattle.currentDayIndex();
        for (uint256 j; j < 8; ++j) {
            uint256 i = (uint256(d) * 9 + j * 4) % PLAYERS;
            _topUpFlip(i);
            if (crapsBattle.daySeatNumberOf(today, cast[i]) != 0) continue;
            if (j < 3) {
                _act("crapsEnterBonusDay", i, address(crapsBattle), 0,
                    abi.encodeWithSignature("enterBonusDay(uint32,uint32,uint16)", uint32(0), BOARD, uint16(1)));
            } else if (j < 6) {
                _act("crapsEnterWindow", i, address(crapsBattle), 0, abi.encodeWithSignature(
                    "enterBonusBattle(uint32,uint256,uint32,uint16)", uint32(0), uint256(1 + j % 3), BOARD, uint16(1)));
            } else if (!game.rngLocked()) {
                _act("crapsEnterJackpot", i, address(crapsBattle), 0, abi.encodeWithSignature(
                    "enterBonusBattle(uint32,uint256,uint32,uint16)", uint32(0), uint256(5), BOARD, uint16(1)));
            }
        }
        if (d % 2 == 0) {
            uint256 i = (uint256(d) * 5 + 1) % PLAYERS;
            _topUpFlip(i);
            _act("crapsBuyFutureDays", i, address(crapsBattle), 0, abi.encodeWithSignature(
                "buyFutureCrapsDays(uint32,uint24,uint8,bool,uint32)", uint32(0), today + 2 + uint24(_rand(d, 700) % 20),
                uint8(1 + _rand(d, 701) % 3), false, BOARD));
        }
        for (uint256 j; j < 2; ++j) {
            uint256 i = (uint256(d) * 7 + j * 11 + 2) % PLAYERS;
            (uint256 normal,) = crapsBattle.passCreditsOf(cast[i]);
            if (normal == 0) continue;
            _act("crapsApplyPasses", i, address(crapsBattle), 0, abi.encodeWithSignature(
                "applyCrapsPasses(uint32,uint24,uint8,bool,uint32)", uint32(0), today + 1 + uint24(_rand(d, 710 + j) % 10),
                uint8(normal > 3 ? 3 : normal), false, BOARD));
        }
        if (d % 7 == 3 && openCustomSlot == 0) {
            (bool ok, bytes memory ret) = _ctx("crapsCreateBattle", false, ContractAddresses.OWNER_GOVERNANCE,
                address(crapsBattle), 0, abi.encodeWithSignature("createBattle(uint32,uint8,uint16,uint24,uint40,bool,uint16)",
                uint32(600), uint8(10), uint16(5), uint24(0), uint40(block.timestamp + 4 hours), true, uint16(0)));
            if (ok) {
                openCustomSlot = abi.decode(ret, (uint64));
                for (uint256 j; j < 4; ++j) {
                    uint256 i = (uint256(d) + j * 7) % PLAYERS;
                    _topUpFlip(i);
                    _act("crapsEnterCustom", i, address(crapsBattle), 0, abi.encodeWithSignature(
                        "enterBattle(uint32,uint64,uint32,uint16)", uint32(0), openCustomSlot, BOARD, uint16(1)));
                }
                _act("crapsDonate", d % PLAYERS, address(crapsBattle), 0,
                    abi.encodeWithSignature("donate(bool,uint256,uint24)", true, uint256(openCustomSlot) - (1 << 40), uint24(10)));
            }
        }
        if (d % 5 == 0) {
            _act("crapsDonateWindow", (d + 3) % PLAYERS, address(crapsBattle), 0,
                abi.encodeWithSignature("donate(bool,uint256,uint24)", false, uint256(3), uint24(5)));
        }
    }

    function _closeCustomBattle() internal {
        if (openCustomSlot == 0) return;
        _act("crapsCloseBattle", 0, address(crapsBattle), 0, abi.encodeWithSignature("closeBattle(uint64)", openCustomSlot));
        openCustomSlot = 0;
    }

    /// @dev Keep a craps player's wallet FLIP above the burn sizes (outside the census).
    function _topUpFlip(uint256 i) internal {
        if (coin.balanceOf(cast[i]) >= 600_000) return;
        vm.prank(address(game));
        coin.mintForGame(cast[i], 2_000_000);
    }

    // ------------------------------------------------------------------------------- AFKing

    mapping(uint256 => bool) internal subscribed;

    /// @dev One new compact subscriber a day (players 18..29), funded; periodic cancel and
    ///      resubscribe; funding top-ups; reward claims. Deliveries happen in mineFlip.
    function _afking(uint24 d) internal {
        uint256 i = 18 + uint256(d) % 12;
        if (!subscribed[i]) {
            uint256 seat = _grantSeat(cast[i]); // cheat-mints a seat when the player holds none (outside the census)
            (bool ok,) = _act("afkingSubscribe", i, address(game), 1 ether,
                abi.encodeCall(game.subscribe, (uint32(0), i % 2 == 0, uint8(1 + i % 4), seat)));
            subscribed[i] = ok;
        } else if (d % 9 == 0) {
            (bool ok,) = _act("afkingCancel", i, address(game), 0,
                abi.encodeCall(game.subscribe, (uint32(0), false, uint8(0), uint256(0))));
            if (ok) subscribed[i] = false;
        } else if (d % 5 == 0) {
            _act("afkingChangeQty", i, address(game), 0,
                abi.encodeCall(game.subscribe, (uint32(0), i % 2 == 0, uint8(1 + (i + d) % 8), uint256(0))));
        }
        if (d % 3 == 1) {
            uint256 k = 18 + (uint256(d) / 3) % 12;
            uint32 kid = game.walletIdOf(cast[k]);
            if (kid != 0) {
                _act("depositAfkingFunding", k, address(game), 0.5 ether, abi.encodeCall(game.depositAfkingFunding, (kid)));
            }
        }
        if (d % 5 == 2) {
            uint32[] memory ids = new uint32[](3);
            for (uint256 j; j < 3; ++j) ids[j] = game.walletIdOf(cast[18 + (uint256(d) + j * 4) % 12]);
            _act("claimAfkingFlip", 18 + uint256(d) % 12, address(game), 0, abi.encodeCall(game.claimAfkingFlip, (ids)));
        }
    }

    // ------------------------------------------------------------------------------- plumbing

    function _act(string memory label, uint256 i, address to, uint256 value, bytes memory data)
        internal
        returns (bool ok, bytes memory ret)
    {
        address p = cast[i];
        if (p.balance < value + 1 ether) vm.deal(p, p.balance + value + 100 ether);
        return _ctx(label, false, p, to, value, data);
    }
}
