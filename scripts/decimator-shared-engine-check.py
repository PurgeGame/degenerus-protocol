#!/usr/bin/env python3
"""Actual-Solidity distribution check, not same-seed replica parity."""
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

contract SharedDiceEVCheck {
    event log_named_uint(string key, uint256 value);
    CrapsEngine engine;
    function setUp() public { engine = new CrapsEngine(); }

    function _peak(bytes32 seed, uint256 id) private view returns (uint256 p) {
        uint256 mem;
        assembly ("memory-safe") { mem := mload(0x40) }
        Craps.SlipResult memory r = engine.settleSlip(
            0, 60, uint256(keccak256(abi.encode("board", seed, id))), 10,
            seed, 3000e18, 0, uint256(uint160(id)), (32 << 8) | 15);
        require(r.stop == Craps.SlipStop.Bust && r.totalRolls <= 1511, "run bounds");
        p = r.peakBankroll;
        assembly ("memory-safe") { mstore(0x40, mem) }
    }

    function test_actualEngineEV() public {
        uint256 worlds = 2000;
        uint256[6] memory weights = [uint256(5000), 10000, 12500, 17833, 20000, 40000];
        uint256[6] memory sums;
        uint256[6] memory squares;
        uint256[6] memory cash;
        uint256[100] memory peaks;
        uint256[100] memory ties;
        bool[100] memory eligible;
        uint256 allocated;
        assembly ("memory-safe") { allocated := mload(0x40) }
        for (uint256 world; world < worlds; ++world) {
            bytes32 seed = keccak256(abi.encode("decimator-ev-engine-check-v1", world));
            uint256 survivors = 1; // Condition focal on heads, then integrate its coin exactly.
            for (uint256 id; id < 100; ++id) {
                peaks[id] = _peak(seed, id + 1);
                ties[id] = uint256(keccak256(abi.encode("tie", seed, id + 1)));
                eligible[id] = id == 0 || uint256(keccak256(abi.encode("final", seed, id + 1))) & 1 != 0;
                if (id != 0 && eligible[id]) ++survivors;
                assembly ("memory-safe") { mstore(0x40, allocated) }
            }
            uint256 winners = survivors < 10 ? survivors : 10;
            for (uint256 w; w < 6; ++w) {
                uint256 rank;
                uint256 focalPeak = peaks[0] * weights[w];
                for (uint256 id = 1; id < 100; ++id) {
                    uint256 otherPeak = peaks[id] * 10000;
                    if (eligible[id] && (otherPeak > focalPeak ||
                        (otherPeak == focalPeak && ties[id] > ties[0]))) ++rank;
                }
                uint256 payout;
                if (rank < winners) {
                    payout = 400000000 / winners;
                    if (rank < 3) {
                        uint256 bonusWeight = rank == 0 ? 5 : rank == 1 ? 3 : 2;
                        payout += 600000000 * bonusWeight / (winners == 1 ? 5 : winners == 2 ? 8 : 10);
                    }
                    payout /= 2;
                    ++cash[w];
                }
                sums[w] += payout;
                squares[w] += payout * payout;
            }
            assembly ("memory-safe") { mstore(0x40, allocated) }
        }
        emit log_named_uint("worlds", worlds);
        for (uint256 w; w < 6; ++w) {
            emit log_named_uint("weight_bps", weights[w]);
            emit log_named_uint("payout_sum_1e9", sums[w]);
            emit log_named_uint("payout_squares_1e18", squares[w]);
            emit log_named_uint("cash_when_heads_count", cash[w]);
        }
    }
}
'''


def main():
    with tempfile.TemporaryDirectory(prefix="decimator-engine-ev-") as raw:
        directory = Path(raw)
        for relative in ("Craps.sol", "CrapsEngine.sol", "CrapsCustomTerms.sol", "libraries/FlipRoundLib.sol"):
            dest = directory / "src" / relative
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / "contracts" / relative, dest)
        (directory / "test").mkdir()
        (directory / "test/SharedDiceEVCheck.t.sol").write_text(SOURCE)
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
        result = subprocess.run(["forge", "test", "--root", str(directory), "--match-test", "test_actualEngineEV", "-vv"],
                                capture_output=True, text=True)
        log = result.stdout + result.stderr
        (ROOT / "docs/DECIMATOR-SHARED-ENGINE-CHECK.txt").write_text(log)
        print(log, flush=True)
        result.check_returncode()
        n = int(re.search(r"worlds: (\d+)", log)[1])
        matches = re.findall(r"weight_bps: (\d+)\s+payout_sum_1e9: (\d+)\s+payout_squares_1e18: (\d+)\s+cash_when_heads_count: (\d+)", log)
        if len(matches) != 6:
            raise RuntimeError("missing engine observations")
        rows = []
        for weight, total, squares, cash in matches:
            mean = int(total) / 1e9 / n
            variance = max(0, (int(squares) / 1e18 - n * mean * mean) / (n - 1))
            rows.append({"weight": int(weight) / 10000, "worlds": n, "ev_pool": mean,
                         "ci95_half_pool": 1.96 * (variance / n) ** 0.5,
                         "cash_probability": 0.5 * int(cash) / n})
        paths = ["contracts/Craps.sol", "contracts/CrapsEngine.sol", "scripts/decimator-shared-engine-check.py"]
        (ROOT / "docs/DECIMATOR-SHARED-ENGINE-CHECK.json").write_text(json.dumps({
            "description": "Actual Solidity engine, 100 shared-dice random-board entries, 15%/+32% boost, no rotation, final coin, top-heavy ladder",
            "rows": rows, "source_sha256": {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in paths},
        }, indent=2) + "\n")


if __name__ == "__main__":
    main()
