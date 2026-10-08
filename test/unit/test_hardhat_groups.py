"""Driver controls with fake Hardhat; exercise the real Node preload, without solc."""

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


RUNNER = Path(__file__).resolve().parents[2] / "scripts/test-hardhat-groups.py"
FAKE_NPX = '''#!/usr/bin/env python3
import os,sys
if "--version" in sys.argv:
 print("fake hardhat 2.x")
else:
 os.execvp("node", ["node", "fake-hardhat.cjs", *sys.argv[1:]])
'''
FAKE_COMPILER = '''class NativeCompiler {
 constructor() { this._pathToSolc = process.execPath; this._solcVersion = "fake-solc"; }
 async compile(input) {
  if (process.env.FAKE_MODE === "compile_error") throw new Error("simulated solc failure");
  return {};
 }
}
module.exports = {NativeCompiler, Compiler: class Compiler extends NativeCompiler {}};
'''
FAKE_HARDHAT = r'''const fs = require("node:fs");
const cp = require("node:child_process");
const mode = process.env.FAKE_MODE || "pass";
let calls = fs.existsSync("calls.json") ? JSON.parse(fs.readFileSync("calls.json")) : [];
calls.push({args:process.argv.slice(2), nodeOptions:process.env.NODE_OPTIONS});
fs.writeFileSync("calls.json", JSON.stringify(calls));
async function main() {
 const originalGame = fs.readFileSync("contracts/Game.sol", "utf8");
 if (mode === "transient_drift") fs.writeFileSync("contracts/Game.sol", "temporarily changed\n");
 if (mode !== "capture_missing") {
  const {NativeCompiler} = require("./node_modules/hardhat/internal/solidity/compiler/index.js");
  for (const value of ["fixture-one\n", "fixture-two\n"]) {
   fs.writeFileSync("contracts/ContractAddresses.sol", value);
   await new NativeCompiler().compile({language:"Solidity", settings:{viaIR:true}, sources:{
    "contracts/ContractAddresses.sol":{content:value},
    "contracts/Game.sol":{content:fs.readFileSync("contracts/Game.sol", "utf8")},
    ...(mode === "unknown_source" ? {"src/Unmanifested.sol":{content:"unmanifested source"}} : {})}});
  }
 }
 if (mode === "transient_drift") fs.writeFileSync("contracts/Game.sol", originalGame);
 if (mode === "sleep") {
  const grandchild = cp.spawn(process.execPath,
   ["-e", 'process.on("SIGTERM",()=>{});setInterval(()=>{},1000)'], {stdio:"ignore"});
  fs.writeFileSync("ready", JSON.stringify({child:process.pid, grandchild:grandchild.pid}));
  setInterval(()=>{},1000); return;
 }
 if (mode === "kill_first" && calls.length === 1) process.kill(process.pid,"SIGKILL");
 if (mode === "drift") fs.writeFileSync("contracts/Game.sol", "changed\n");
 if (mode === "add_source") fs.writeFileSync("contracts/Unexpected.sol", "unexpected\n");
 if (mode === "golden_drift") fs.writeFileSync("scripts/layout/golden/DegenerusGame.json", "{}\n");
 if (mode === "dependency_drift") fs.writeFileSync("lib/forge-std/Library.sol", "changed dependency\n");
 const doc = process.env.FAKE_DOC_PATH || "docs/AUDIT.md";
 if (mode === "doc_add") { fs.mkdirSync(require("node:path").dirname(doc),{recursive:true}); fs.writeFileSync(doc, "added\n"); }
 if (mode === "doc_remove") fs.unlinkSync(doc);
 if (mode === "missing") console.log("No Mocha execution happened");
 else if (mode === "zero") console.log("  0 passing (1ms)\n  4 pending");
 else if (mode === "failed") console.log("  1 passing (1ms)\n  1 failing");
 else if (mode === "ambiguous") console.log("  2 passing (1ms)\n  3 passing (1ms)");
 else console.log("\u001b[32m  2 passing (1ms)\u001b[0m\n  1 pending");
 if (mode === "exit_fail") process.exitCode=7;
}
main().catch(error=>{console.error(error);process.exitCode=12;});
'''


class HardhatGroupsDriverTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for name in ("scripts", "contracts", "bin", "test", "node_modules/hardhat/internal/solidity/compiler"):
            (self.root / name).mkdir(parents=True)
        shutil.copyfile(RUNNER, self.root / "scripts/test-hardhat-groups.py")
        self.pins = self.root / "contracts/ContractAddresses.sol"
        self.pins.write_bytes(b"original pins\r\n")
        (self.root / "contracts/Game.sol").write_text("original game\n")
        (self.root / "hardhat.config.js").write_text('const TEST_DIR_ORDER = ["second", "first"];\n')
        (self.root / "package.json").write_text('{"type":"commonjs"}\n')
        (self.root / "node_modules/hardhat/package.json").write_text('{"version":"fake"}\n')
        (self.root / "node_modules/hardhat/internal/solidity/compiler/index.js").write_text(FAKE_COMPILER)
        (self.root / "fake-hardhat.cjs").write_text(FAKE_HARDHAT)
        (self.root / "bin/npx").write_text(FAKE_NPX)
        (self.root / "bin/npx").chmod(0o755)
        (self.root / "bin/npm").write_text('#!/bin/sh\nprintf "fake npm\\n"\n')
        (self.root / "bin/npm").chmod(0o755)
        self.env = {**os.environ, "PATH": str(self.root / "bin") + os.pathsep + os.environ["PATH"]}

    def sources(self, folder, count):
        directory = self.root / "test" / folder
        directory.mkdir(parents=True, exist_ok=True)
        result = []
        for i in range(count):
            path = directory / f"Case{i:02d}.test.js"
            path.write_text("// fake test\n")
            result.append(str(path.relative_to(self.root)))
        return result

    def run_driver(self, *args, **env):
        done = subprocess.run([sys.executable, "scripts/test-hardhat-groups.py", *args],
                              cwd=self.root, env={**self.env, **env}, capture_output=True, text=True)
        self.assertEqual(self.pins.read_bytes(), b"original pins\r\n", done.stdout + done.stderr)
        return done

    def rows(self, log_dir=None):
        return json.loads(((log_dir or self.root / ".audit-test-logs/hardhat") / "summary.json").read_text())

    def test_default_order_comes_from_config_and_each_file_gets_a_process(self):
        first = self.sources("first", 2)
        second = self.sources("second", 1)
        done = self.run_driver()
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        rows = self.rows()
        self.assertEqual([row["selected_files"] for row in rows], [[p] for p in second + first])
        self.assertTrue(all(row["passed"] == 2 and row["pending"] == 1 for row in rows))
        run = self.root / ".audit-test-logs/hardhat" / rows[0]["run_id"]
        meta = json.loads((run / "run.json").read_text())
        self.assertEqual(meta["physical_batches"], 3)
        self.assertEqual(meta["completed_batches"], 3)
        self.assertEqual(meta["test_dir_order"], ["second", "first"])
        self.assertEqual(meta["original_pins_sha256"], meta["pins_restored_sha256"])
        self.assertIn("hardhat", meta["versions"])

    def test_unassigned_test_directory_fails_instead_of_silently_omitting_it(self):
        self.sources("first", 1)
        paths = self.sources("not-in-config", 1)
        done = self.run_driver("--list")
        self.assertNotEqual(done.returncode, 0)
        self.assertIn("Unassigned Hardhat test sources", done.stderr)
        self.assertIn(paths[0], done.stderr)
        self.assertFalse((self.root / "calls.json").exists())

    def test_symlinked_libraries_are_captured_and_drift_fails(self):
        self.sources("first", 1)
        shared = self.root / "shared-library"
        shared.mkdir()
        (shared / "Library.sol").write_text("original dependency\n")
        (shared / "cycle").symlink_to(shared, target_is_directory=True)
        for directory, name in (("lib", "forge-std"), ("node_modules", "linked")):
            (self.root / directory).mkdir(exist_ok=True)
            (self.root / directory / name).symlink_to(shared, target_is_directory=True)
        done = self.run_driver()
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        row = self.rows()[-1]
        inputs = json.loads((self.root / ".audit-test-logs/hardhat" / row["source_manifest"]).read_text())
        for path in ("lib/forge-std/Library.sol", "node_modules/linked/Library.sol"):
            self.assertEqual(inputs.get(path), hashlib.sha256(b"original dependency\n").hexdigest())
        self.assertFalse(any("/cycle/" in path for path in inputs))
        done = self.run_driver(FAKE_MODE="dependency_drift")
        self.assertNotEqual(done.returncode, 0)
        self.assertIn("lib/forge-std/Library.sol", self.rows()[-1]["source_drift"])

    def test_override_and_flags_preserve_explicit_order(self):
        paths = self.sources("first", 3)
        done = self.run_driver("--file", paths[2], "--file", paths[0], "--max-files", "2",
                               "--grep", "a literal pattern", "--no-compile")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        row = self.rows()[0]
        self.assertEqual(row["selected_files"], [paths[2], paths[0]])
        self.assertEqual(row["command"][-3:], ["--grep", "a literal pattern", "--no-compile"])

    def test_legacy_positional_paths_select_files_and_grep_values_stay_flags(self):
        paths = self.sources("first", 3)
        done = self.run_driver(paths[2], paths[0], "--grep", paths[1], "--no-compile")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        rows = self.rows()
        self.assertEqual([r["selected_files"] for r in rows], [[paths[2]], [paths[0]]])
        self.assertTrue(all(r["command"][-3:] == ["--grep", paths[1], "--no-compile"] for r in rows))
        self.assertNotEqual(self.run_driver("--unknown-flag", paths[1]).returncode, 0)

    def test_live_capture_keeps_both_transient_pin_versions_before_compiler(self):
        self.sources("first", 1)
        done = self.run_driver()
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        row = self.rows()[0]
        self.assertEqual(row["live_compiler_invocations"], 2)
        folder = self.root / ".audit-test-logs/hardhat" / row["run_id"] / row["batch"]
        values = set()
        for path in (folder / "compiler-inputs").glob("*.json"):
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), path.stem)
            values.add(json.loads(path.read_text())["sources"]["contracts/ContractAddresses.sol"]["content"])
        self.assertEqual(values, {"fixture-one\n", "fixture-two\n"})
        self.assertEqual((folder / "ContractAddresses.after.sol").read_text(), "fixture-two\n")

    def test_selected_sources_outside_captured_roots_fail_before_tools(self):
        other = self.root / "checks/Case.test.js"
        other.parent.mkdir()
        other.write_text("// unmanifested test\n")
        explicit = self.run_driver("--file", "checks/Case.test.js")
        self.assertNotEqual(explicit.returncode, 0)
        self.assertIn("captured", explicit.stderr)
        (self.root / "hardhat.config.js").write_text(
            'const TEST_DIR_ORDER = ["."];\nconst config = {paths:{tests:"checks"}};\n')
        discovered = self.run_driver()
        self.assertNotEqual(discovered.returncode, 0)
        self.assertIn("captured", discovered.stderr)
        self.assertFalse((self.root / "calls.json").exists())

    def test_custom_config_and_tsconfig_redirects_fail_before_tools(self):
        self.sources("first", 1)
        (self.root / "custom.config.js").write_text('const TEST_DIR_ORDER = ["first"];\n')
        for flags, env in ((("--config", "custom.config.js"), {}),
                           (("--tsconfig=other.json",), {}),
                           ((), {"HARDHAT_CONFIG":"custom.config.js"}),
                           ((), {"TS_NODE_PROJECT":"other.json"})):
            with self.subTest(flags=flags, env=env):
                self.assertNotEqual(self.run_driver(*flags, **env).returncode, 0)
        self.assertFalse((self.root / "calls.json").exists())

    def test_unknown_live_compiler_source_is_not_exempt(self):
        self.sources("first", 1)
        done = self.run_driver(FAKE_MODE="unknown_source")
        self.assertEqual(done.returncode, 1)
        self.assertEqual(self.rows()[0]["compiler_source_drift"], ["src/Unmanifested.sol"])

    def test_input_is_preserved_when_compiler_fails(self):
        self.sources("first", 1)
        done = self.run_driver(FAKE_MODE="compile_error")
        self.assertEqual(done.returncode, 1)
        row = self.rows()[0]
        self.assertEqual(row["hardhat_exit_code"], 12)
        self.assertEqual(row["live_compiler_invocations"], 1)
        folder = self.root / ".audit-test-logs/hardhat" / row["run_id"] / row["batch"]
        self.assertEqual(len(list((folder / "compiler-inputs").glob("*.json"))), 1)

    def test_cached_build_inputs_are_labeled_separately(self):
        self.sources("first", 1)
        folder = self.root / "artifacts/build-info"
        folder.mkdir(parents=True)
        cached = {"language": "Solidity", "sources": {"old.sol": {"content": "old source"}}}
        (folder / "cached.json").write_text(json.dumps({"id":"cached", "solcVersion":"old-solc",
            "solcLongVersion":"old-long", "input":cached, "output":{"large":"x" * 200000}}))
        done = self.run_driver()
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        row = self.rows()[0]
        dest = self.root / ".audit-test-logs/hardhat" / row["run_id"] / row["batch"]
        record = json.loads((dest / "cached-inputs-before.json").read_text())[0]
        self.assertEqual(record["origin"], "before-available-build-info")
        self.assertEqual(record["solcVersion"], "old-solc")
        self.assertEqual(json.loads((dest / "compiler-inputs" / (record["input_sha256"] + ".json")).read_text()), cached)

    def test_missing_zero_failed_ambiguous_and_process_failure_are_not_green(self):
        self.sources("first", 1)
        for mode in ("missing", "zero", "failed", "ambiguous", "exit_fail", "capture_missing"):
            with self.subTest(mode=mode):
                done = self.run_driver(FAKE_MODE=mode)
                self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
                self.assertTrue(self.rows()[-1]["errors"])

    def test_failures_and_unique_logs_survive_batches_and_reruns(self):
        self.sources("first", 2)
        self.assertEqual(self.run_driver(FAKE_MODE="kill_first").returncode, 1)
        self.assertEqual([r["exit_code"] for r in self.rows()], [1, 0])
        self.assertEqual(self.run_driver().returncode, 0)
        rows = self.rows()
        self.assertEqual([r["exit_code"] for r in rows], [1, 0, 0, 0])
        self.assertEqual(len({r["log"] for r in rows}), 4)

    def test_non_pin_source_mutation_or_addition_invalidates_and_stops_campaign(self):
        self.sources("first", 2)
        for mode, expected in (("drift", "contracts/Game.sol"), ("add_source", "contracts/Unexpected.sol")):
            with self.subTest(mode=mode):
                done = self.run_driver(FAKE_MODE=mode)
                self.assertEqual(done.returncode, 1)
                row = self.rows()[-1]
                self.assertIn(expected, row["source_drift"])
                self.assertEqual(row["batch"], "batch-001")

    def test_transient_non_pin_compiler_source_change_cannot_hide_behind_restoration(self):
        self.sources("first", 1)
        done = self.run_driver(FAKE_MODE="transient_drift")
        self.assertEqual(done.returncode, 1)
        self.assertEqual((self.root / "contracts/Game.sol").read_text(), "original game\n")
        self.assertEqual(self.rows()[0]["compiler_source_drift"], ["contracts/Game.sol"])

    def test_golden_layout_and_audit_doc_creation_removal_are_input_drift(self):
        self.sources("first", 1)
        golden = self.root / "scripts/layout/golden/DegenerusGame.json"
        golden.parent.mkdir(parents=True)
        golden.write_text('{"storage": []}\n')
        cases = [("golden_drift", "scripts/layout/golden/DegenerusGame.json")]
        cases += [(mode, path) for path in ("docs/AUDIT.md", "docs/audit/snapshot.json", "scope.txt")
                  for mode in ("doc_add", "doc_remove")]
        for mode, path in cases:
            with self.subTest(mode=mode):
                done = self.run_driver(FAKE_MODE=mode, FAKE_DOC_PATH=path)
                self.assertEqual(done.returncode, 1)
                self.assertIn(path, self.rows()[-1]["source_drift"])

    def test_shared_summary_appends_both_isolated_histories(self):
        self.sources("first", 1)
        with tempfile.TemporaryDirectory() as other:
            peer = Path(other) / "checkout"
            shutil.copytree(self.root, peer)
            log_dir = self.root / "shared-evidence"
            cmd = [sys.executable, "scripts/test-hardhat-groups.py", "--log-dir", str(log_dir)]
            children = [subprocess.Popen(cmd, cwd=root, env=self.env, stdout=subprocess.PIPE,
                                         stderr=subprocess.PIPE, text=True) for root in (self.root, peer)]
            try:
                for child in children:
                    out, err = child.communicate(timeout=15)
                    self.assertEqual(child.returncode, 0, out + err)
            finally:
                for child in children:
                    if child.poll() is None: child.kill()
                    child.communicate()
            self.assertEqual((peer / PIN_NAME).read_bytes(), b"original pins\r\n")
            rows = self.rows(log_dir)
            self.assertEqual(len(rows), 2)
            self.assertEqual(len({row["run_id"] for row in rows}), 2)

    def test_sigterm_stops_process_group_and_restores_exact_pins(self):
        self.sources("first", 1)
        child = subprocess.Popen([sys.executable, "scripts/test-hardhat-groups.py"], cwd=self.root,
                                 env={**self.env, "FAKE_MODE":"sleep"}, stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, text=True)
        self.addCleanup(lambda: child.poll() is None and child.kill())
        deadline = time.monotonic() + 10
        while not (self.root / "ready").exists() and time.monotonic() < deadline: time.sleep(0.02)
        self.assertTrue((self.root / "ready").exists(), "fake Hardhat did not start")
        pids = json.loads((self.root / "ready").read_text())
        child.send_signal(signal.SIGTERM)
        child.communicate(timeout=8)
        self.assertEqual(child.returncode, 1)
        self.assertEqual(self.pins.read_bytes(), b"original pins\r\n")
        self.assertIn("SIGTERM", self.rows()[-1]["errors"][0])
        for pid in pids.values():
            status = Path(f"/proc/{pid}/status")
            if status.exists(): self.assertRegex(status.read_text(), r"State:\s+Z")

    def test_list_is_read_only_and_invalid_selections_fail(self):
        self.sources("first", 3)
        result = self.run_driver("--list", "--max-files", "2")
        self.assertEqual(result.returncode, 0)
        self.assertIn("3 test files, 2 physical batches", result.stdout)
        self.assertFalse((self.root / ".audit-test-logs").exists())
        for args in [("--max-files", "0"), ("--file", "missing.test.js")]:
            self.assertNotEqual(self.run_driver(*args).returncode, 0)
        (self.root / "hardhat.config.js").write_text('const TEST_DIR_ORDER = ["first", "first"];')
        self.assertNotEqual(self.run_driver().returncode, 0)
        self.assertFalse((self.root / "calls.json").exists())

    def test_invalid_history_is_preserved(self):
        self.sources("first", 1)
        folder = self.root / ".audit-test-logs/hardhat"
        folder.mkdir(parents=True)
        (folder / "summary.json").write_text("{broken history")
        self.assertNotEqual(self.run_driver().returncode, 0)
        self.assertEqual((folder / "summary.json").read_text(), "{broken history")
        self.assertFalse((self.root / "calls.json").exists())

    def test_evidence_path_spaces_and_shell_characters_are_literal(self):
        self.sources("first", 1)
        log_dir = self.root / "literal space $(never-run) evidence"
        done = self.run_driver("--log-dir", str(log_dir))
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual(self.rows(log_dir)[0]["live_compiler_invocations"], 2)


PIN_NAME = "contracts/ContractAddresses.sol"

if __name__ == "__main__":
    unittest.main()
