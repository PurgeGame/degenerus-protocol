#!/usr/bin/env python3
"""Engine-only EV sample; does NOT invoke the legacy simulator's system model.

Reuse its economic dice replica with the CURRENT Solidity roll budget. The
replica uses a fast mixer instead of keccak; results are Monte Carlo estimates,
not EVM parity proofs or guaranteed loss floors. Twenty independent blocks per
cell expose some sampling variation, but can still miss rare heavy-tail wins.
"""
import argparse
import re
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def program(blocks, per_block):
    source = (ROOT / "scripts/craps-high-water-system-sim.cpp").read_text()
    engine = (ROOT / "contracts/Craps.sol").read_text()
    budget = re.search(r"_SLIP_ROLL_BUDGET\s*=\s*([0-9_]+);", engine)
    assert budget, "Current Solidity roll budget not found"
    budget = int(budget[1].replace("_", ""))
    # Reused code is only the engine and sampling helpers before the old main.
    source = source.split("int main(int argc, char** argv) {")[0]
    source, changes = re.subn(r"constexpr int kRollBudget = [0-9']+;",
                              f"constexpr int kRollBudget = {budget};", source)
    assert changes == 1
    for name, value in (("_MAX_SLIP_HANDS", 512), ("_MAX_ROLLS", 512),
                        ("_ESC_HANDS", 3), ("_ROTATION_UPLIFT", 5)):
        match = re.search(rf"{name}\s*=\s*([0-9_]+);", engine)
        assert match and int(match[1].replace("_", "")) == value, name
    assert "_ESC_CAP = type(uint32).max" in engine
    packed = re.search(r"function _shooterBoostTerms[\s\S]*?return\s*\(\s*(0x[0-9a-fA-F]+)", engine)
    assert packed, "Current shooter boost table not found"
    value = int(packed[1], 16)
    assert [((value >> (16*i)) & 255) for i in range(8)] == [15,14,12,11,9,8,6,5]
    assert [((value >> (16*i + 8)) & 255) for i in range(8)] == [32,29,29,29,29,24,23,18]
    source += r'''
int main() {
    std::cout << std::fixed << std::setprecision(6);
    std::cout << "strategy\tfield_size\tsamples\tengine_loss_pct\tblock_se_pct\tmin_block_loss_pct\tmax_block_loss_pct\n";
    const int blocks = BLOCK_COUNT, perBlock = PER_BLOCK;
    for (Strategy strategy : {Strategy::Blank, Strategy::Sharp4}) {
        for (int n : {1, 40, 200}) {
            gCalibrationFieldSize = n;
            long double sum = 0, sum2 = 0, low = 100, high = -100;
            for (int block = 0; block < blocks; ++block) {
                auto c = calibrateFixed(strategy, perBlock, keyed(20260928, static_cast<u64>(strategy), block), 5);
                const long double edge = 100 * (c.bankroll - c.paid) / c.bankroll;
                sum += edge; sum2 += edge * edge;
                low = std::min(low, edge); high = std::max(high, edge);
            }
            auto mean = sum / blocks;
            auto se = std::sqrt((sum2 / blocks - mean * mean) / (blocks - 1));
            std::cout << strategyName(strategy) << '\t' << n << '\t' << blocks * perBlock
                      << '\t' << mean << '\t' << se << '\t' << low << '\t' << high << std::endl;
        }
    }
}
'''.replace("BLOCK_COUNT", str(blocks)).replace("PER_BLOCK", str(per_block))
    return source


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--blocks", type=int, default=20)
    parser.add_argument("--per-block", type=int, default=100000)
    parser.add_argument("--output", type=Path, default=ROOT / "docs/CRAPS-ENGINE-EV-2026-09-28.tsv")
    args = parser.parse_args()
    if args.blocks < 2 or args.per_block < 1:
        parser.error("need at least two nonempty sample blocks")
    with tempfile.TemporaryDirectory(prefix="craps-engine-ev-") as directory:
        source, binary = Path(directory) / "calibration.cpp", Path(directory) / "calibration"
        source.write_text(program(args.blocks, args.per_block))
        subprocess.run(["g++", "-O3", "-std=c++20", str(source), "-o", str(binary)], check=True)
        with args.output.open("w") as out:
            subprocess.run([str(binary)], stdout=out, check=True)
    print(args.output)


if __name__ == "__main__":
    main()
