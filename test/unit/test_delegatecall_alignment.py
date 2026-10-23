"""Gas options must preserve delegatecall target validation."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class DelegatecallOptionsTests(unittest.TestCase):
    def check_target(self, target, options):
        with tempfile.TemporaryDirectory() as directory:
            contracts = Path(directory)
            (contracts / "interfaces").mkdir()
            for name in ("ContractAddresses.sol", "interfaces/IDegenerusGameModules.sol"):
                shutil.copyfile(ROOT / "contracts" / name, contracts / name)
            (contracts / "Probe.sol").write_text(
                "contract Probe { function run() external {\n"
                f"ContractAddresses.{target}.delegatecall{options}(\n"
                "abi.encodeWithSelector(IDegenerusGameDecimatorModule.runDecimatorWork.selector, 1000000));\n"
                "} }\n"
            )
            return subprocess.run(
                ["bash", str(ROOT / "scripts/check-delegatecall-alignment.sh")],
                cwd=ROOT, env={**os.environ, "CONTRACTS_DIR": str(contracts)},
                capture_output=True, text=True,
            )

    def test_matches_plain_and_gas_limited_targets(self):
        for options in ("", "{gas: childGas}"):
            with self.subTest(options=options):
                result = self.check_target("GAME_DECIMATOR_MODULE", options)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("1/1 delegatecall sites aligned", result.stdout)

    def test_gas_options_do_not_hide_wrong_target(self):
        result = self.check_target("GAME_JACKPOT_MODULE", "{gas: childGas}")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("expects GAME_DECIMATOR_MODULE but targets GAME_JACKPOT_MODULE", result.stdout)

    def check_dispatch(self, body):
        with tempfile.TemporaryDirectory() as directory:
            contracts = Path(directory)
            (contracts / "interfaces").mkdir()
            for name in ("ContractAddresses.sol", "interfaces/IDegenerusGameModules.sol"):
                shutil.copyfile(ROOT / "contracts" / name, contracts / name)
            (contracts / "GameMiner.sol").write_text(
                "contract GameMiner { function run() external {\n"
                "address target; bytes memory callData;\n" + body +
                "\ntarget.delegatecall{gas: forwarded}(callData);\n} }\n"
            )
            return subprocess.run(
                ["bash", str(ROOT / "scripts/check-delegatecall-alignment.sh")],
                cwd=ROOT, env={**os.environ, "CONTRACTS_DIR": str(contracts)},
                capture_output=True, text=True,
            )

    def test_long_nested_dispatch_keeps_its_parent_target(self):
        body = "if (request) {\ntarget = ContractAddresses.GAME_RNG_MODULE;\n"
        body += "uint256 padding;\n" * 15
        body += "if (daily) {\ncallData = abi.encodeWithSelector(IDegenerusGameRngModule.requestDailyRng_g8190.selector);\n} }\n"
        result = self.check_dispatch(body)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        result = self.check_dispatch(body.replace("target = ContractAddresses.GAME_RNG_MODULE", "target = ContractAddresses.GAME_JACKPOT_MODULE"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("expects GAME_RNG_MODULE but targets GAME_JACKPOT_MODULE", result.stdout)

    def test_sibling_or_unknown_assignment_cannot_certify_dispatch(self):
        for assignment in ("", "target = suppliedTarget;\n"):
            result = self.check_dispatch(
                "if (first) { target = ContractAddresses.GAME_RNG_MODULE; } else {\n" + assignment +
                "callData = abi.encodeWithSelector(IDegenerusGameRngModule.requestDailyRng_g8190.selector);\n}\n"
            )
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertIn("orphan selector", result.stdout)


if __name__ == "__main__":
    unittest.main()
