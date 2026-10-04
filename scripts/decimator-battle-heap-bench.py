#!/usr/bin/env python3
"""Isolated on-chain top-K leaderboard experiment; changes no production contracts.

Run with python3 scripts/decimator-battle-heap-bench.py. Requires forge.
Gas is measured for cold external calls, excluding transaction intrinsic gas and
entry/cursor/pool bookkeeping. These are component measurements, not a whole-router bound.
"""
import hashlib
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

SOURCE = r'''
// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import {Craps} from "../src/Craps.sol";
import {CrapsEngine} from "../src/CrapsEngine.sol";

interface Vm { function cool(address target) external; }

// Two storage words per node. rankKey stands for a bounded score plus a random
// tie tag; entryId is a stable pointer into the event's frozen entries.
// Exact production score packing and full tie-collision handling are separate work.
contract BattleHeap {
    struct Node { uint256 rankKey; uint256 entryId; }
    Node[100] internal heap;
    uint256 public size;
    uint256 public immutable capacity;
    constructor(uint256 cap) { require(cap > 0 && cap <= 100); capacity = cap; }

    function offer(uint256 rankKey, uint256 entryId) external returns (bool accepted, uint256 moves) {
        Node memory next = Node(rankKey, entryId);
        uint256 n = size;
        if (n < capacity) {
            uint256 insertPos = n;
            size = n + 1;
            while (insertPos != 0) {
                uint256 parent = (insertPos - 1) >> 1;
                Node memory above = heap[parent];
                if (!_less(next, above)) break;
                heap[insertPos] = above;
                insertPos = parent;
                ++moves;
            }
            heap[insertPos] = next;
            return (true, moves);
        }
        if (!_less(heap[0], next)) return (false, 0);
        uint256 pos;
        while (2 * pos + 1 < n) {
            uint256 child = 2 * pos + 1;
            Node memory below = heap[child];
            if (child + 1 < n) {
                Node memory right = heap[child + 1];
                if (_less(right, below)) { ++child; below = right; }
            }
            if (!_less(below, next)) break;
            heap[pos] = below;
            pos = child;
            ++moves;
        }
        heap[pos] = next;
        return (true, moves);
    }

    function _less(Node memory a, Node memory b) private pure returns (bool) {
        return a.rankKey < b.rankKey || (a.rankKey == b.rankKey && a.entryId < b.entryId);
    }

    function node(uint256 i) external view returns (Node memory) { require(i < size); return heap[i]; }

    function podium() external view returns (Node[3] memory best) {
        for (uint256 i; i < size; ++i) {
            Node memory v = heap[i];
            for (uint256 j; j < 3; ++j) {
                if (_less(best[j], v)) {
                    for (uint256 k = 2; k > j; --k) best[k] = best[k - 1];
                    best[j] = v;
                    break;
                }
            }
        }
    }
}

// Experiment-only admission gate. The caller supplies already-frozen event data
// and the score from a completed run; production must enforce those bindings and
// its monotonic entry cursor. This is not a deployable public entry API.
contract FinalFlipGate {
    bytes32 constant FINAL_FLIP_TAG = keccak256("degenerus.decimator.final-flip.v1");
    BattleHeap public immutable board;
    constructor(uint256 cap) { board = new BattleHeap(cap); }

    function eligible(uint256 word, uint256 eventId, uint256 entryId) public pure returns (bool) {
        return uint256(keccak256(abi.encode(FINAL_FLIP_TAG, word, eventId, entryId))) & 1 == 1;
    }

    function submit(uint256 rankKey, uint256 entryId, uint256 word, uint256 eventId)
        external returns (bool survived, bool accepted, uint256 moves)
    {
        if (!eligible(word, eventId, entryId)) return (false, false, 0);
        (accepted, moves) = board.offer(rankKey, entryId);
        return (true, accepted, moves);
    }
}

contract BattleHeapExperiment {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    event log_named_uint(string key, uint256 value);
    BattleHeap full50;
    BattleHeap full100;
    BattleHeap almost100;
    BattleHeap empty100;
    CrapsEngine engine;

    // Prefill in setUp, so tests begin with committed nonzero storage rather than
    // discounting replacements as dirty writes created in the same test call.
    function setUp() public {
        full50 = new BattleHeap(50);
        full100 = new BattleHeap(100);
        almost100 = new BattleHeap(100);
        empty100 = new BattleHeap(100);
        engine = new CrapsEngine();
        for (uint256 i = 1; i <= 100; ++i) {
            if (i <= 50) full50.offer(i, i);
            if (i < 100) almost100.offer(i, i);
            full100.offer(i, i);
        }
    }

    function _offer(string memory label, BattleHeap target, uint256 key, uint256 id) private {
        vm.cool(address(target));
        uint256 beforeGas = gasleft();
        (, uint256 moves) = target.offer(key, id);
        uint256 used = beforeGas - gasleft();
        require(moves <= 6, "heap path exceeded six moves");
        emit log_named_uint(label, used);
    }
    function test_coldReject100() public { _offer("reject_100", full100, 0, 1000); }
    function test_coldReject50() public { _offer("reject_50", full50, 0, 1000); }
    function test_coldReplace100() public { _offer("replace_100", full100, 1000, 1000); }
    function test_coldReplace50() public { _offer("replace_50", full50, 1000, 1000); }
    function test_coldFirstInsert() public { _offer("first_insert", empty100, 1, 1); }
    function test_coldFullHeightInsert() public { _offer("full_height_insert", almost100, 0, 1000); }
    function test_coldPodiumScan() public {
        vm.cool(address(full100));
        uint256 beforeGas = gasleft();
        BattleHeap.Node[3] memory best = full100.podium();
        uint256 used = beforeGas - gasleft();
        require(best[0].rankKey == 100 && best[1].rankKey == 99 && best[2].rankKey == 98);
        emit log_named_uint("podium_scan_100", used);
    }

    function test_topKAgainstScalarRankingAndReverseArrival() public {
        BattleHeap forward = new BattleHeap(100);
        BattleHeap reverse = new BattleHeap(100);
        uint256[400] memory keys;
        // Intentionally frequent ties exercise the total comparison order.
        for (uint256 i; i < 400; ++i) {
            keys[i] = uint256(keccak256(abi.encode("heap-check", i))) % 200;
            (, uint256 moves) = forward.offer(keys[i], i + 1);
            require(moves <= 6);
        }
        for (uint256 i = 400; i > 0; --i) {
            (, uint256 moves) = reverse.offer(keys[i - 1], i);
            require(moves <= 6);
        }
        require(forward.size() == 100 && reverse.size() == 100);
        bool[400] memory seen;
        for (uint256 i; i < 100; ++i) {
            BattleHeap.Node memory v = forward.node(i);
            require(!seen[v.entryId - 1]); seen[v.entryId - 1] = true;
            uint256 better;
            for (uint256 j; j < 400; ++j) {
                if (keys[j] > v.rankKey || (keys[j] == v.rankKey && j + 1 > v.entryId)) ++better;
            }
            require(better < 100, "not a genuine top-100 entry");
        }
        for (uint256 i; i < 100; ++i) {
            require(seen[reverse.node(i).entryId - 1], "arrival order changed winner set");
        }
    }

    function test_finalFlipDisqualifiesRawChampionAndRefillsPlaces() public {
        FinalFlipGate gate = new FinalFlipGate(2);
        uint256 heads;
        uint256 tails;
        uint256 rawChampion;
        for (uint256 id = 1; heads < 2 || tails == 0; ++id) {
            require(id < 1000, "fixture search exhausted");
            if (gate.eligible(12345, 91, id)) {
                if (heads == 2) continue;
                ++heads;
                (bool survived, bool accepted,) = gate.submit(heads * 100, id, 12345, 91);
                require(survived && accepted);
            } else if (tails == 0) {
                rawChampion = id;
                (bool survived, bool accepted, uint256 moves) = gate.submit(1000000, id, 12345, 91);
                require(!survived && !accepted && moves == 0, "tails entered leaderboard");
                ++tails;
            }
        }
        BattleHeap board = gate.board();
        require(board.size() == 2, "did not refill paid places");
        BattleHeap.Node[3] memory top = board.podium();
        require(top[0].rankKey == 200 && top[1].rankKey == 100);
        require(top[0].entryId != rawChampion && top[1].entryId != rawChampion);
        // A different score or delayed retry cannot change an entry's eligibility.
        (bool retry, bool admitted,) = gate.submit(type(uint256).max, rawChampion, 12345, 91);
        require(!retry && !admitted && board.size() == 2);
    }

    function test_finalFlipEmptyAndUnderfilledBoards() public {
        FinalFlipGate gate = new FinalFlipGate(10);
        uint256 losingEntries;
        uint256 firstSurvivor;
        for (uint256 id = 1; losingEntries < 10 || firstSurvivor == 0; ++id) {
            require(id < 1000);
            if (gate.eligible(9876, 92, id)) {
                if (firstSurvivor == 0) firstSurvivor = id;
            } else if (losingEntries < 10) {
                gate.submit(1000000, id, 9876, 92);
                ++losingEntries;
            }
        }
        require(gate.board().size() == 0, "all-tails field has a winner");
        gate.submit(1, firstSurvivor, 9876, 92);
        require(gate.board().size() == 1, "underfilled field invented winners");
        require(gate.board().podium()[0].entryId == firstSurvivor);
    }

    function test_finalFlipTopKMatchesEligibleReferenceInBothOrders() public {
        FinalFlipGate forward = new FinalFlipGate(50);
        FinalFlipGate reverse = new FinalFlipGate(50);
        uint256[400] memory keys;
        bool[400] memory eligible;
        uint256 survivors;
        for (uint256 i; i < 400; ++i) {
            keys[i] = uint256(keccak256(abi.encode("final-flip-score", i))) % 200;
            eligible[i] = forward.eligible(777, 93, i + 1);
            if (eligible[i]) ++survivors;
            (bool passed,, uint256 moves) = forward.submit(keys[i], i + 1, 777, 93);
            require(passed == eligible[i] && moves <= 5);
        }
        require(survivors > 50 && survivors < 400, "fixture must exercise both outcomes");
        for (uint256 i = 400; i > 0; --i) reverse.submit(keys[i - 1], i, 777, 93);
        BattleHeap a = forward.board();
        BattleHeap b = reverse.board();
        require(a.size() == 50 && b.size() == 50);
        bool[400] memory seen;
        for (uint256 i; i < 50; ++i) {
            BattleHeap.Node memory v = a.node(i);
            require(eligible[v.entryId - 1] && !seen[v.entryId - 1]);
            seen[v.entryId - 1] = true;
            uint256 better;
            for (uint256 j; j < 400; ++j) {
                if (eligible[j] && (keys[j] > v.rankKey || (keys[j] == v.rankKey && j + 1 > v.entryId))) ++better;
            }
            require(better < 50, "not top-50 among survivors");
        }
        for (uint256 i; i < 50; ++i) require(seen[b.node(i).entryId - 1]);
    }

    function test_engineComponentGas() public {
        uint256 totalGas;
        uint256 maxGas;
        uint256 totalRolls;
        uint256 maxRolls;
        for (uint256 i; i < 256; ++i) {
            bytes32 seed = keccak256(abi.encode("decimator-gas", i));
            uint256 scatter = uint256(keccak256(abi.encode(seed, "board")));
            vm.cool(address(engine));
            uint256 beforeGas = gasleft();
            Craps.SlipResult memory r = engine.settleSlip(
                0, 60, scatter, 10, seed, 3000e18, 0, address(uint160(i + 1)), (72 << 8) | 15);
            uint256 used = beforeGas - gasleft();
            totalGas += used; totalRolls += r.totalRolls;
            if (used > maxGas) maxGas = used;
            if (r.totalRolls > maxRolls) maxRolls = r.totalRolls;
            require(r.totalRolls <= 1511 && r.stop == Craps.SlipStop.Bust);
        }
        emit log_named_uint("engine_sample_count", 256);
        emit log_named_uint("engine_mean_gas", totalGas / 256);
        emit log_named_uint("engine_max_sample_gas", maxGas);
        emit log_named_uint("engine_mean_rolls", totalRolls / 256);
        emit log_named_uint("engine_max_sample_rolls", maxRolls);
    }
}
'''


def main():
    with tempfile.TemporaryDirectory(prefix="decimator-heap-") as raw:
        directory = Path(raw)
        for relative in ("Craps.sol", "CrapsEngine.sol", "CrapsCustomTerms.sol", "libraries/FlipRoundLib.sol"):
            dest = directory / "src" / relative
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / "contracts" / relative, dest)
        (directory / "test").mkdir()
        (directory / "test/BattleHeapExperiment.t.sol").write_text(SOURCE)
        (directory / "foundry.toml").write_text('''[profile.default]
src = "src"
test = "test"
libs = []
solc_version = "0.8.34"
via_ir = true
optimizer = true
optimizer_runs = 1000
evm_version = "osaka"
gas_limit = 30000000000
block_gas_limit = 30000000000
''')
        result = subprocess.run(["forge", "test", "--root", str(directory), "-vv"],
                                capture_output=True, text=True)
        log = result.stdout + result.stderr
        output = ROOT / "docs/DECIMATOR-BATTLE-HEAP-GAS.txt"
        output.write_text(log)
        print(log)
        result.check_returncode()
        rows = {label: int(value) for label, value in re.findall(r"^\s+([a-z_0-9]+): (\d+)\s*$", log, re.M)}
        artifact = {
            "component_gas": rows,
            "assumptions": ["Isolated Solidity 0.8.34, via-IR, optimizer runs 1000, Osaka EVM",
                            "Two storage words per heap node; cold external calls",
                            "Excludes transaction intrinsic gas, entries, cursor, rewards, ETH reserves and credits",
                            "Heap gas rows exclude the added final-flip gate; three gate tests check eligibility semantics",
                            "Engine sample maximum is not a worst-case bound",
                            "Prototype only; production score widths and RNG domains remain to be specified"],
            "sources": {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest()
                        for p in ("contracts/Craps.sol", "contracts/CrapsEngine.sol",
                                  "scripts/decimator-battle-heap-bench.py")},
        }
        (ROOT / "docs/DECIMATOR-BATTLE-HEAP-GAS.json").write_text(json.dumps(artifact, indent=2) + "\n")


if __name__ == "__main__":
    main()
