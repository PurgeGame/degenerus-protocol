"""Exercise the Foundry driver with fake tools; no Solidity build or pin edits in the repo."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest


RUNNER = Path(__file__).resolve().parents[2] / "scripts/test-foundry-groups.py"
FAKE_TOOL = '''#!/usr/bin/env python3
import json, os, signal, sys, time
from pathlib import Path
if Path(sys.argv[0]).name == "node":
    Path("contracts/ContractAddresses.sol").write_text("patched\\n")
    raise SystemExit(int(os.environ.get("FAKE_PATCH_EXIT", "0")))
if "--version" in sys.argv:
    print("forge fake-test-tool")
    raise SystemExit(0)
if "config" in sys.argv:
    print(json.dumps({"src":os.environ.get("FOUNDRY_SRC", "contracts"),
        "test":os.environ.get("FOUNDRY_TEST", "test"), "libs":["lib", "node_modules"],
        "include_paths":json.loads(os.environ.get("FOUNDRY_INCLUDE_PATHS", "[]")),
        "remappings":[os.environ["FOUNDRY_REMAPPINGS"]] if "FOUNDRY_REMAPPINGS" in os.environ else []}))
    raise SystemExit(0)
state = Path("calls.json")
calls = json.loads(state.read_text()) if state.exists() else []
calls.append({"args": sys.argv[1:], "fuzz_runs": os.environ.get("FOUNDRY_FUZZ_RUNS"),
              "invariant_depth": os.environ.get("FOUNDRY_INVARIANT_DEPTH")})
state.write_text(json.dumps(calls))
mode = os.environ.get("FAKE_MODE", "pass")
if mode == "kill_first" and len(calls) == 1:
    os.kill(os.getpid(), signal.SIGKILL)
if mode == "sleep":
    Path("ready").write_text(str(os.getpid()))
    time.sleep(30)
if mode == "missing":
    print("compiler succeeded, but no tests ran")
elif mode == "zero":
    print("Ran 0 test suites in 0s: 0 tests passed, 0 failed, 0 skipped")
elif mode == "skipped_only":
    print("Ran 1 test suite in 0s: 0 tests passed, 0 failed, 1 skipped")
elif mode == "failed":
    print("Ran 1 test suite in 0s: 1 test passed, 1 failed, 0 skipped")
else:
    if mode == "drift":
        Path("contracts/Game.sol").write_text("changed during compile\\n")
    if mode == "bytecode_drift":
        Path("contracts/mocks/Reference.hex").write_text("0x6001\\n")
    if mode == "dependency_drift":
        Path("lib/forge-std/Library.sol").write_text("changed dependency\\n")
    print("Ran 1 test suite in 0s: 2 tests passed, 0 failed, 0 skipped")
'''


class FoundryGroupsDriverTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for name in ("scripts", "contracts", "bin", "test"):
            (self.root / name).mkdir()
        shutil.copyfile(RUNNER, self.root / "scripts/test-foundry-groups.py")
        self.pins = self.root / "contracts/ContractAddresses.sol"
        self.pins.write_text("original pins\n")
        (self.root / "contracts/Game.sol").write_text("original game\n")
        (self.root / "foundry.toml").write_text("[fuzz]\nruns = 1000\n[invariant]\ndepth = 128\n")
        for name in ("node", "forge"):
            path = self.root / "bin" / name
            path.write_text(FAKE_TOOL)
            path.chmod(0o755)
        self.env = {**os.environ, "PATH": str(self.root / "bin") + os.pathsep + os.environ["PATH"],
                    "FOUNDRY_FUZZ_RUNS": "77", "FOUNDRY_INVARIANT_DEPTH": "91"}

    def sources(self, directory, count, suffix=".t.sol"):
        root = self.root / "test" / directory
        root.mkdir(parents=True, exist_ok=True)
        paths = []
        for i in range(count):
            path = root / f"Case{i:03d}{suffix}"
            path.write_text(f"// source {directory} {i}\n")
            paths.append(str(path.relative_to(self.root)))
        return paths

    def run_driver(self, *args, **env):
        result = subprocess.run([sys.executable, "scripts/test-foundry-groups.py", *args],
                                cwd=self.root, env={**self.env, **env}, capture_output=True, text=True)
        self.assertEqual(self.pins.read_text(), "original pins\n", result.stderr)
        return result

    def rows(self):
        return json.loads((self.root / ".audit-test-logs/foundry/summary.json").read_text())

    def test_integration_alias_shards_every_source_and_records_actual_inputs(self):
        selected = self.sources("gas", 41)
        excluded = self.sources("fuzz", 3)
        support = self.sources("helpers", 1, ".sol")
        result = self.run_driver("--group", "integration-gas")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        rows = self.rows()
        self.assertEqual([row["source_files"] for row in rows], [20, 20, 1])
        self.assertEqual(sorted(path for row in rows for path in row["selected_sources"]), selected)
        log_dir = self.root / ".audit-test-logs/foundry"
        for row in rows:
            self.assertEqual(row["group"], "integration-gas")
            args = row["command"]
            self.assertEqual(args.count("--force"), 1, "each batch rebuilds a coherent artifact set")
            skipped = {args[i + 1] for i, arg in enumerate(args[:-1]) if arg == "--skip"}
            self.assertTrue(set(excluded) <= skipped)
            self.assertFalse(set(support) & skipped)
            self.assertEqual(set(selected) - skipped, set(row["selected_sources"]))
            manifest_path = log_dir / row["input_manifest"]
            self.assertEqual(hashlib.sha256(manifest_path.read_bytes()).hexdigest(), row["input_manifest_sha256"])
            inputs = json.loads(manifest_path.read_text())
            self.assertEqual(inputs["contracts/ContractAddresses.sol"], hashlib.sha256(b"patched\n").hexdigest())
            self.assertTrue(set(selected + excluded + support) <= inputs.keys())
            self.assertTrue((log_dir / row["log"]).exists())
        calls = json.loads((self.root / "calls.json").read_text())
        self.assertTrue(all(call["fuzz_runs"] == "77" and call["invariant_depth"] == "91" for call in calls))

    def test_passing_group_keeps_existing_size_and_override_can_split_it(self):
        self.sources("fuzz/invariant", 21)
        self.assertEqual(self.run_driver("--group", "invariants").returncode, 0)
        self.assertEqual([row["source_files"] for row in self.rows()], [21])
        self.assertEqual(self.run_driver("--group", "invariants", "--max-files", "7").returncode, 0)
        rows = self.rows()
        self.assertEqual([row["source_files"] for row in rows], [21, 7, 7, 7])
        self.assertNotEqual(rows[0]["run_id"], rows[1]["run_id"])

    def test_symlinked_libraries_are_captured_and_drift_fails(self):
        self.sources("gas", 1)
        shared = self.root / "shared-library"
        shared.mkdir()
        (shared / "Library.sol").write_text("original dependency\n")
        (shared / "cycle").symlink_to(shared, target_is_directory=True)
        for directory, name in (("lib", "forge-std"), ("node_modules", "linked")):
            (self.root / directory).mkdir(exist_ok=True)
            (self.root / directory / name).symlink_to(shared, target_is_directory=True)
        result = self.run_driver("--group", "integration-gas")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        row = self.rows()[-1]
        inputs = json.loads((self.root / ".audit-test-logs/foundry" / row["input_manifest"]).read_text())
        for path in ("lib/forge-std/Library.sol", "node_modules/linked/Library.sol"):
            self.assertEqual(inputs.get(path), hashlib.sha256(b"original dependency\n").hexdigest())
        self.assertFalse(any("/cycle/" in path for path in inputs))
        result = self.run_driver("--group", "integration-gas", FAKE_MODE="dependency_drift")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("source/build inputs changed during this batch", self.rows()[-1]["errors"])

    def test_focused_selection_and_forge_limits_are_preserved(self):
        gas = self.sources("gas", 3)
        fuzz = self.sources("fuzz", 3)
        result = self.run_driver("--file", gas[1], "--file", fuzz[2], "--max-files", "1",
                                 "--force", "--fuzz-runs", "13", "--fuzz-seed", "0x1234")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        rows = self.rows()
        self.assertEqual({path for row in rows for path in row["selected_sources"]}, {gas[1], fuzz[2]})
        self.assertTrue(all(row["command"][-4:] == ["--fuzz-runs", "13", "--fuzz-seed", "0x1234"] for row in rows))
        self.assertTrue(all(row["command"].count("--force") == 1 for row in rows))
        self.assertEqual(len(rows), 2)

    def test_missing_zero_or_failed_totals_fail_even_when_forge_exits_zero(self):
        self.sources("gas", 1)
        for mode in ("missing", "zero", "failed"):
            with self.subTest(mode=mode):
                result = self.run_driver("--group", "integration-gas", FAKE_MODE=mode)
                self.assertNotEqual(result.returncode, 0)
                row = self.rows()[-1]
                self.assertEqual(row["forge_exit_code"], 0)
                self.assertEqual(row["exit_code"], 1)
                self.assertTrue(row["errors"])

    def test_killed_batch_is_retained_across_later_batches_and_successful_rerun(self):
        self.sources("gas", 21)
        failed = self.run_driver("--group", "integration-gas", FAKE_MODE="kill_first")
        self.assertNotEqual(failed.returncode, 0)
        rows = self.rows()
        self.assertEqual([row["exit_code"] for row in rows], [1, 0])
        self.assertEqual(rows[0]["forge_exit_code"], -signal.SIGKILL)
        self.assertEqual(self.run_driver("--group", "integration-gas").returncode, 0)
        self.assertEqual([row["exit_code"] for row in self.rows()], [1, 0, 0, 0])
        self.assertEqual(len({row["log"] for row in self.rows()}), 4)

    def test_skipped_only_batch_is_not_execution(self):
        self.sources("gas", 1)
        result = self.run_driver("--group", "integration-gas", FAKE_MODE="skipped_only")
        self.assertNotEqual(result.returncode, 0)
        row = self.rows()[0]
        self.assertEqual(row["forge_exit_code"], 0)
        self.assertEqual((row["passed"], row["failed"], row["skipped"]), (0, 0, 1))
        self.assertIn("zero test suites or tests executed", row["errors"])

    def test_source_relocation_flags_fail_before_patching(self):
        self.sources("gas", 1)
        for flags in (("--root", "other"), ("--root=other",), ("-Cother",),
                      ("--config-path", "other.toml"), ("-R", "lib/=external/"),
                      ("--lib-paths=external",), ("--remappings-env", "OTHER_MAP")):
            with self.subTest(flags=flags):
                result = self.run_driver("--group", "integration-gas", *flags)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("relocation", result.stderr)
        self.assertFalse((self.root / "calls.json").exists())
        self.assertFalse((self.root / ".audit-test-logs").exists())

    def test_effective_environment_paths_outside_manifest_fail_before_patching(self):
        self.sources("gas", 1)
        for override in ({"FOUNDRY_SRC":"other"}, {"FOUNDRY_TEST":"other"},
                         {"FOUNDRY_INCLUDE_PATHS":'["external"]'},
                         {"FOUNDRY_REMAPPINGS":"lib/=external/"}, {"FOUNDRY_CONFIG":"other.toml"}):
            with self.subTest(override=override):
                result = self.run_driver("--group", "integration-gas", **override)
                self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / "calls.json").exists())
        self.assertFalse((self.root / ".audit-test-logs").exists())

    def test_isolated_checkouts_can_append_to_shared_summary(self):
        self.sources("gas", 21)
        log_dir = self.root / ".audit-test-logs/foundry"
        with tempfile.TemporaryDirectory() as second:
            peer = Path(second) / "checkout"
            shutil.copytree(self.root, peer)
            command = [sys.executable, "scripts/test-foundry-groups.py", "--group", "integration-gas",
                       "--log-dir", str(log_dir)]
            processes = [subprocess.Popen(command, cwd=checkout,
                                          env={**self.env, "FAKE_MODE": "kill_first"},
                                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                         for checkout in (self.root, peer)]
            try:
                for process in processes:
                    output, errors = process.communicate(timeout=5)
                    self.assertEqual(process.returncode, 1, output + errors)
            finally:
                for process in processes:
                    if process.poll() is None:
                        process.kill()
                    process.communicate()
            self.assertEqual((peer / "contracts/ContractAddresses.sol").read_text(), "original pins\n")
        self.assertEqual(self.pins.read_text(), "original pins\n")
        rows = self.rows()
        self.assertEqual(len(rows), 4)
        self.assertEqual(sorted(row["exit_code"] for row in rows), [0, 0, 1, 1])
        self.assertEqual(len({row["run_id"] for row in rows}), 2)
        self.assertEqual(len({row["log"] for row in rows}), 4)

    def test_source_drift_invalidates_result(self):
        self.sources("gas", 1)
        result = self.run_driver("--group", "integration-gas", FAKE_MODE="drift")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("source/build inputs changed during this batch", self.rows()[0]["errors"])

    def test_vm_readfile_bytecode_is_recorded_and_drift_invalidates_result(self):
        self.sources("gas", 1)
        blob = self.root / "contracts/mocks/Reference.hex"
        blob.parent.mkdir(parents=True)
        blob.write_text("0x6000\n")
        result = self.run_driver("--group", "integration-gas", FAKE_MODE="bytecode_drift")
        self.assertNotEqual(result.returncode, 0)
        row = self.rows()[0]
        self.assertIn("source/build inputs changed during this batch", row["errors"])
        manifest = json.loads((self.root / ".audit-test-logs/foundry" / row["input_manifest"]).read_text())
        self.assertEqual(manifest["contracts/mocks/Reference.hex"], hashlib.sha256(b"0x6000\n").hexdigest())

    def test_patch_failure_restores_pins_and_records_failure(self):
        self.sources("gas", 1)
        result = self.run_driver("--group", "integration-gas", FAKE_PATCH_EXIT="7")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.rows()[0]["group"], "runner")
        self.assertFalse((self.root / "calls.json").exists())

    def test_sigterm_stops_active_tool_and_restores_pins(self):
        self.sources("gas", 1)
        process = subprocess.Popen([sys.executable, "scripts/test-foundry-groups.py", "--group", "integration-gas"],
                                   cwd=self.root, env={**self.env, "FAKE_MODE": "sleep"},
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        def cleanup():
            if process.poll() is None:
                process.kill()
            process.communicate()
        self.addCleanup(cleanup)
        deadline = time.monotonic() + 5
        while not (self.root / "ready").exists() and time.monotonic() < deadline:
            time.sleep(0.02)
        self.assertTrue((self.root / "ready").exists(), "fake forge never started")
        child_pid = int((self.root / "ready").read_text())
        process.send_signal(signal.SIGTERM)
        process.communicate(timeout=5)
        self.assertNotEqual(process.returncode, 0)
        self.assertEqual(self.pins.read_text(), "original pins\n")
        self.assertIn("SIGTERM", self.rows()[-1]["errors"][0])
        self.assertEqual(self.rows()[-1]["batch"], "integration-gas-01")
        self.assertIn("command", self.rows()[-1])
        with self.assertRaises(ProcessLookupError):
            os.kill(child_pid, 0)

    def test_list_reports_physical_batches_without_mutation(self):
        self.sources("gas", 41)
        result = self.run_driver("--group", "integration-gas", "--list")
        self.assertEqual(result.returncode, 0)
        self.assertIn("41 source files, 3 batches", result.stdout)
        self.assertFalse((self.root / "calls.json").exists())
        self.assertFalse((self.root / ".audit-test-logs").exists())

    def test_empty_selection_and_unassigned_source_fail_before_patching(self):
        self.assertNotEqual(self.run_driver().returncode, 0)
        self.sources("unassigned", 1)
        self.assertNotEqual(self.run_driver().returncode, 0)
        self.assertFalse((self.root / ".audit-test-logs").exists())

    def test_invalid_existing_summary_is_not_overwritten(self):
        self.sources("gas", 1)
        log_dir = self.root / ".audit-test-logs/foundry"
        log_dir.mkdir(parents=True)
        summary = log_dir / "summary.json"
        summary.write_text("{broken evidence")
        self.assertNotEqual(self.run_driver("--group", "integration-gas").returncode, 0)
        self.assertEqual(summary.read_text(), "{broken evidence")
        self.assertFalse((self.root / "calls.json").exists())


if __name__ == "__main__":
    unittest.main()
