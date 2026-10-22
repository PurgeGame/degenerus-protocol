// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {GameFunding} from "../helpers/GameFunding.sol";

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MineFlipAdmission} from "../fuzz/helpers/MineFlipAdmission.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

/// @dev Storage-context helper for the cover-box pin: reads an entry of a box buffer and sets the two
///      scalars a max-price deity sale needs. Etched over the Game for one call, then restored.
contract ChainPinBoxProbe is DegenerusGameStorage {
    function boxAt(uint48 buffer, uint32 position) external view returns (uint256) {
        return _boxEntryAt(buffer, position);
    }

    function setDeitySales(uint8 sales) external {
        deityPassSales = sales;
    }

    function setLevel(uint24 lvl) external {
        level = lvl;
    }
}

/// @title ChainPinWorkers
/// @notice Pins for the Degenerette and cover-box couplings of the mineFlip chain.
/// @dev F-D3: nothing between a Degenerette worker's first ETH win and its pool flush may write the
///      prize pools, or the flush overwrites it and the result depends on how the queue was chunked.
///      The pin resolves one bet queue in one call and in many calls and compares the final value of
///      EVERY storage slot written, in every account.
///      F-B4: `recordCoverBox` masks neither the per-box units nor the quantity, so every producer
///      must hand it units <= LB_UNITS_MAX and a quantity <= 100.
contract ChainPinWorkers is DeployProtocol {
    uint256 private constant FULL = 16_000_000;
    uint8 private constant A_DEGEN = 11;
    uint256 private constant LB_UNITS_MAX = 2_000_000;

    bytes32 private constant LOOT_BOX_BUY = keccak256("LootBoxBuy(uint32,uint48,uint32,uint256)");

    struct Rec {
        address account;
        bytes32 slot;
        bytes32 init;
        bytes32 val;
    }

    struct Recs {
        Rec[] items;
        uint256 n;
    }

    bytes private realCode;
    bytes private boxProbeCode;

    address[] private bettors;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        mockVRF.fundSubscription(1, 1_000_000 ether);
        vm.deal(address(game), 400_000 ether);
        realCode = address(game).code;
        boxProbeCode = type(ChainPinBoxProbe).runtimeCode;
        _finishSubscriptionWindow();
    }

    // =====================================================================
    // F-D3: Degenerette resolution is chunk-invariant down to storage
    // =====================================================================

    function test_DegeneretteQueueResolvesToIdenticalStateInOneCallAndInMany() public {
        vm.pauseGasMetering();
        _placeBets();
        _seedFuturePool(5_000 ether);
        vm.warp(block.timestamp + 1 days);

        // Up to the daily request: stop when the engine waits for the word.
        for (uint256 i; i < 400; ++i) {
            uint8 a = game.nextMinerAction();
            if (a == 2) break;
            require(a != 0, "no daily request was reached");
            game.mineFlip(0);
        }
        require(game.nextMinerAction() == 2, "request not outstanding");
        uint256 requested = vm.snapshotState();

        // A word whose resolution pays ETH, so the pool flush is exercised.
        uint256 salt;
        uint256 atDegenerette;
        uint256 missed;
        for (; salt < 40; ++salt) {
            vm.revertToState(requested);
            _fulfillWith(uint256(keccak256(abi.encode("pin-degenerette-word", salt))));
            if (!_toDegenerette()) {
                ++missed;
                continue;
            }
            atDegenerette = vm.snapshotState();
            _resolveAndSettle(FULL, false);
            if (_paidSomething()) break;
        }
        require(
            salt < 40,
            string.concat("no word produced an ETH payout; stage missed ", vm.toString(missed), " last actions ", vm.toString(lastSeen))
        );

        vm.revertToState(atDegenerette);
        (uint256 callsA, Recs memory a) = _resolveAndSettle(FULL, false);
        bytes32 digestA = _digest();
        vm.revertToState(atDegenerette);
        (uint256 callsB, Recs memory b) = _resolveAndSettle(400_000, true);
        bytes32 digestB = _digest();
        // A mid-size chunking: the first starting budget that splits the queue into 3..18 calls.
        uint256 callsC;
        Recs memory c;
        bytes32 digestC;
        for (uint256 start = 900_000; start <= 1_400_000; start += 20_000) {
            vm.revertToState(atDegenerette);
            (callsC, c) = _resolveAndSettle(start, true);
            digestC = _digest();
            if (callsC >= 3 && callsC <= 18) break;
        }

        emit log_named_uint("calls, one full call budget", callsA);
        emit log_named_uint("calls, cheapest admitted budget", callsB);
        emit log_named_uint("calls, mid-size chunks", callsC);
        emit log_named_uint("slots written (full budget)", a.n);
        require(callsB >= 12 && callsB > callsA, "the tight budget did not split the queue");
        require(callsC >= 3 && callsC <= 18, "no starting budget gave a mid-size split");

        uint256 bad = _diff(a, b) + _diff(a, c);
        assertEq(bad, 0, "final storage differs between one call and many (see logged slots)");
        assertEq(digestA, digestB, "explicit digest: full vs tight budget");
        assertEq(digestA, digestC, "explicit digest: full vs mid budget");
    }

    function _placeBets() private {
        for (uint256 i; i < 4; ++i) {
            address p = address(uint160(0xD3D30000 + i));
            bettors.push(p);
            vm.deal(p, 100_000 ether);
            _giveWalletId(p);
            vm.prank(address(game));
            coin.mintForGame(p, 500_000);
        }
        uint256 placed;
        for (uint256 i; i < 24; ++i) {
            address p = bettors[i % 4];
            uint8 symbol = uint8((i * 5) % 24);
            uint8 spins = uint8(3 + (i % 8));
            vm.prank(p);
            if (i % 3 == 2) {
                try game.placeDegeneretteBet(0, 1, uint128(200 + 200 * (i % 4)), uint8(3 + i % 5), symbol) {
                    ++placed;
                } catch {}
            } else {
                uint128 stake = uint128(0.01 ether * (1 + i % 5));
                try game.placeDegeneretteBet{value: uint256(stake) * spins}(0, 0, stake, spins, symbol) {
                    ++placed;
                } catch {}
            }
        }
        require(placed >= 20, "bets were not placed");
    }

    function _seedFuturePool(uint256 future) private {
        uint256 packed = uint256(vm.load(address(game), bytes32(GameSlots.PRIZE_POOLS_PACKED)));
        uint256 low = packed & ((uint256(1) << 128) - 1);
        vm.store(address(game), bytes32(GameSlots.PRIZE_POOLS_PACKED), bytes32((future << 128) | low));
    }

    function _fulfillWith(uint256 word) private {
        uint256 req = mockVRF.lastRequestId();
        mockVRF.fulfillRandomWords(req, word);
    }

    /// @dev Crank to the Degenerette stage. False if the engine passes it without stopping there.
    bytes private lastSeen;

    function _toDegenerette() private returns (bool) {
        delete lastSeen;
        for (uint256 i; i < 400; ++i) {
            uint8 a = game.nextMinerAction();
            lastSeen.push(bytes1(a));
            if (a == A_DEGEN) return true;
            if (a == 0 || a == 2) return false;
            _stepMinimal();
        }
        return false;
    }

    /// @dev One mineFlip with the smallest allowance that succeeds (bisection over snapshots), so a call
    ///      cannot run through the stage the test wants to stop at.
    function _stepMinimal() private {
        uint256 lo = 200_000;
        uint256 hi = 30_000_000;
        while (hi - lo > 1_000) {
            uint256 mid = (lo + hi) / 2;
            uint256 snap = vm.snapshotState();
            (bool ok,) = address(game).call{gas: mid}(abi.encodeWithSignature("mineFlip(uint32)", uint32(0)));
            vm.revertToStateAndDelete(snap);
            if (ok) hi = mid;
            else lo = mid;
        }
        game.mineFlip{gas: hi}(0);
    }

    function _paidSomething() private view returns (bool) {
        for (uint256 i; i < bettors.length; ++i) {
            if (game.claimableWinningsOf(bettors[i]) > 1) return true;
        }
        return false;
    }

    /// @dev Resolve the stage with `gas` per call (or, when `tight`, with the cheapest budget that admits
    ///      progress for each call), then drain the rest of the day at full budget so every variant ends at
    ///      the same point. Returns the last value of every slot written, in memory (a snapshot revert
    ///      would erase contract storage).
    function _resolveAndSettle(uint256 gas, bool escalate) private returns (uint256 calls, Recs memory out) {
        out.items = new Rec[](8000);
        address miner = address(0xAAAA0001);
        vm.startStateDiffRecording();
        for (uint256 i; i < 600 && game.nextMinerAction() == A_DEGEN; ++i) {
            uint256 g = gas;
            while (true) {
                vm.prank(miner);
                (bool ok,) = address(game).call{gas: g}(abi.encodeWithSignature("mineFlip(uint32)", uint32(0)));
                if (ok) break;
                require(escalate && g < FULL, "stage call failed");
                g = g * 5 / 4;
            }
            ++calls;
        }
        for (uint256 i; i < 300; ++i) {
            uint8 a = game.nextMinerAction();
            if (a == 0 || a == 2) break;
            vm.prank(miner);
            game.mineFlip(0);
        }
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        _collect(acc, out);
    }

    function _collect(Vm.AccountAccess[] memory acc, Recs memory out) private pure {
        for (uint256 i; i < acc.length; ++i) {
            if (acc[i].reverted) continue;
            for (uint256 j; j < acc[i].storageAccesses.length; ++j) {
                Vm.StorageAccess memory sa = acc[i].storageAccesses[j];
                if (!sa.isWrite || sa.reverted) continue;
                bool found;
                for (uint256 k; k < out.n; ++k) {
                    if (out.items[k].account == sa.account && out.items[k].slot == sa.slot) {
                        out.items[k].val = sa.newValue;
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    require(out.n < out.items.length, "recorder capacity");
                    out.items[out.n++] = Rec(sa.account, sa.slot, sa.previousValue, sa.newValue);
                }
            }
        }
    }

    /// @dev Slots whose final value differs. A slot written by only one side is compared with the other
    ///      side's untouched (initial) value.
    function _diff(Recs memory x, Recs memory y) private returns (uint256 bad) {
        for (uint256 i; i < x.n; ++i) {
            bytes32 other = x.items[i].init;
            for (uint256 k; k < y.n; ++k) {
                if (y.items[k].account == x.items[i].account && y.items[k].slot == x.items[i].slot) {
                    other = y.items[k].val;
                    break;
                }
            }
            if (other != x.items[i].val) {
                ++bad;
                emit log_named_address("differing account", x.items[i].account);
                emit log_named_bytes32("differing slot", x.items[i].slot);
                emit log_named_bytes32("  full budget", x.items[i].val);
                emit log_named_bytes32("  split", other);
            }
        }
        for (uint256 k; k < y.n; ++k) {
            bool seen;
            for (uint256 i; i < x.n; ++i) {
                if (y.items[k].account == x.items[i].account && y.items[k].slot == x.items[i].slot) {
                    seen = true;
                    break;
                }
            }
            if (!seen && y.items[k].val != y.items[k].init) {
                ++bad;
                emit log_named_address("differing account (split only)", y.items[k].account);
                emit log_named_bytes32("differing slot", y.items[k].slot);
            }
        }
    }

    function _digest() private view returns (bytes32 h) {
        h = keccak256(
            abi.encode(
                game.futurePrizePoolView(),
                game.nextPrizePoolView(),
                game.currentPrizePoolView(),
                game.claimablePoolView(),
                address(game).balance,
                coin.totalSupply()
            )
        );
        for (uint256 i; i < bettors.length; ++i) {
            h = keccak256(abi.encode(h, game.claimableWinningsOf(bettors[i]), coin.balanceOf(bettors[i])));
        }
    }

    // =====================================================================
    // F-B4: cover-box producers stay inside the entry word's fields
    // =====================================================================

    function test_CoverBoxProducersStayInsideTheEntryFields() public {
        vm.pauseGasMetering();
        address buyer = address(0xB04B0001);
        vm.deal(buyer, 100_000 ether);
        _giveWalletId(buyer);
        uint32 id = game.walletIdOf(buyer);

        // Whale pass: quantities across the fold into 100 boxes, up to the 1,000 maximum.
        uint256[5] memory quantities = [uint256(1), 99, 100, 101, 1000];
        for (uint256 i; i < quantities.length; ++i) {
            uint256 q = quantities[i];
            vm.recordLogs();
            vm.prank(buyer);
            try game.purchaseWhalePass{value: q * 4 ether}(0, q, bytes32(0)) {}
            catch (bytes memory why) {
                revert(string.concat("whale pass ", vm.toString(q), " reverted: ", vm.toString(why)));
            }
            _assertCoverEntry(id, q > 100 ? 100 : q, "whale pass");
        }

        // Lazy pass.
        vm.recordLogs();
        vm.prank(buyer);
        try game.purchaseLazyPass{value: 5 ether}(0, bytes32(0)) {
            _assertCoverEntry(id, 1, "lazy pass");
        } catch {
            vm.getRecordedLogs();
        }

        // Deity pass at the maximum price: the 30th paid sale, 19,200 ETH (5% box below level 10; the 10% box
        // of the same sale is checked in ChainPinGameDrive).
        address whale = address(0xB04B0002);
        vm.deal(whale, 60_000 ether);
        _giveWalletId(whale);
        uint32 whaleId = game.walletIdOf(whale);
        vm.etch(address(game), boxProbeCode);
        ChainPinBoxProbe(address(game)).setDeitySales(29);
        vm.etch(address(game), realCode);
        vm.recordLogs();
        vm.prank(whale);
        try game.purchaseDeityPass{value: 19_200 ether}(0, 9, bytes32(0)) {}
        catch (bytes memory why) {
            revert(string.concat("deity pass reverted: ", vm.toString(why)));
        }
        uint256 units = _assertCoverEntry(whaleId, 1, "deity pass");
        assertEq(units, 960_000, "the early-rate deity box is 5% of 19,200 ETH");
    }

    /// @dev The LootBoxBuy of the recorded purchase names its queue position; the stored entry must hold
    ///      exactly the units and quantity the producer meant, in range, with no spill past bit 84.
    function _assertCoverEntry(uint32 id, uint256 expectedQty, string memory what) private returns (uint256 units) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics[0] != LOOT_BOX_BUY) continue;
            if (uint32(uint256(logs[i].topics[1])) != id) continue;
            uint48 buffer = uint48(uint256(logs[i].topics[2]));
            (uint32 position, uint256 amount) = abi.decode(logs[i].data, (uint32, uint256));
            vm.etch(address(game), boxProbeCode);
            uint256 entry = ChainPinBoxProbe(address(game)).boxAt(buffer, position);
            vm.etch(address(game), realCode);
            found = true;
            units = BoxOrderLib.boUnits(entry);
            assertEq(BoxOrderLib.boId(entry), id, string.concat(what, ": wallet id field"));
            assertEq(BoxOrderLib.boCount(entry), expectedQty, string.concat(what, ": quantity field"));
            assertLe(BoxOrderLib.boCount(entry), 100, string.concat(what, ": quantity above 100"));
            assertEq(units, amount / (expectedQty * BoxOrderLib.SCALE), string.concat(what, ": units field wrapped"));
            assertLe(units, LB_UNITS_MAX, string.concat(what, ": units above LB_UNITS_MAX"));
            assertEq(BoxOrderLib.boHighBits(entry), 0, string.concat(what, ": bits spilled past the entry"));
        }
        assertTrue(found, string.concat(what, ": no cover box recorded"));
    }

    // =====================================================================
    // F-B4 (sDGNRS): its automatic whale buy, the largest folded quantity any producer sends
    // =====================================================================

    function test_SdgnrsAutomaticWhaleBuyCoverBoxStaysInRange() public {
        vm.pauseGasMetering();
        GameFunding.credit(2, 30_000 ether);
        // The buy is attempted once per level above level 0, in the next subscriber pass.
        vm.etch(address(game), boxProbeCode);
        ChainPinBoxProbe(address(game)).setLevel(1);
        vm.etch(address(game), realCode);
        vm.warp(block.timestamp + 1 days);
        vm.recordLogs();
        bool bought;
        for (uint256 i; i < 40 && !bought; ++i) {
            uint8 a = game.nextMinerAction();
            if (a == 0 || a == 2) {
                if (a == 0) break;
                uint256 req = mockVRF.lastRequestId();
                mockVRF.fulfillRandomWords(req, uint256(keccak256("pin-sdgnrs-word")));
                continue;
            }
            game.mineFlip(0);
            Vm.Log[] memory logs = vm.getRecordedLogs();
            for (uint256 j; j < logs.length; ++j) {
                if (logs[j].emitter != address(game) || logs[j].topics[0] != LOOT_BOX_BUY) continue;
                if (uint32(uint256(logs[j].topics[1])) != 2) continue;
                uint48 buffer = uint48(uint256(logs[j].topics[2]));
                (uint32 position, uint256 amount) = abi.decode(logs[j].data, (uint32, uint256));
                vm.etch(address(game), boxProbeCode);
                uint256 entry = ChainPinBoxProbe(address(game)).boxAt(buffer, position);
                vm.etch(address(game), realCode);
                uint256 qty = BoxOrderLib.boCount(entry);
                if (qty <= 1) continue;
                bought = true;
                assertLe(qty, 100, "sDGNRS whale buy: quantity above 100");
                assertEq(qty, 100, "sDGNRS whale buy: the fold is 100 boxes");
                assertEq(BoxOrderLib.boUnits(entry), amount / (qty * BoxOrderLib.SCALE), "units wrapped");
                assertLe(BoxOrderLib.boUnits(entry), LB_UNITS_MAX, "units above LB_UNITS_MAX");
                assertEq(BoxOrderLib.boHighBits(entry), 0, "bits spilled past the entry");
            }
        }
        assertTrue(bought, "the sDGNRS automatic whale buy never recorded a cover box");
    }
}
