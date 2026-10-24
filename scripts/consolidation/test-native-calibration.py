#!/usr/bin/env python3
"""Unit checks for the native replay oracle's state and event comparisons."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("native_calibration", Path(__file__).with_name("native-calibration.py"))
n = importlib.util.module_from_spec(spec)
spec.loader.exec_module(n)
A = "0x" + "12" * 20
S = n.b.word(1)
T = n.b.word(2)


class NativeReplayOracle(unittest.TestCase):
    def test_native_call_log_order_and_reverted_children(self):
        spec = importlib.util.spec_from_file_location("fork_budgets", Path(__file__).with_name("native-fork-budgets.py"))
        fork = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(fork)
        before = {"position": "0x0", "data": "before"}
        child = {"position": "0x0", "data": "child"}
        after = {"position": "0x2", "data": "after"}
        frame = {"logs": [before, after], "calls": [
            {"logs": [child]}, {"error": "execution reverted", "logs": [{"position": "0x0", "data": "reverted"}]}]}
        self.assertEqual(fork.ordered_logs(frame), [before, child, after])

    def test_foundry_embedded_and_encoded_json_have_identical_meaning(self):
        expected = {A: {S: "0x7"}}
        self.assertEqual(n.json_value(expected), expected)
        self.assertEqual(n.json_value(n.json.dumps(expected)), expected)
        self.assertEqual(n.json_value("[]"), [])

    def test_native_intrinsic_uses_client_budget_and_refund_upper_bound(self):
        meter = {"first": 16_777_216 - 16_000, "last": {"gas": 16_777_216 - 116_000, "cost": 0, "op": 0xF3},
                 "refund": 1_000, "receiptGas": 115_000, "error": None}
        gas = n.gas_meter.measured_gas(meter, 16_777_216)
        self.assertEqual(gas["intrinsicGas"], 16_000)
        self.assertEqual(gas["frameExecutionBudgetConsumed"], 100_000)
        self.assertEqual(gas["grossGasUpperBound"], 116_000)
        for gross in range(1, 101):
            for refund in range(101):
                receipt = gross - min(refund, gross // 5)
                upper = receipt + min(refund, (receipt + 3) // 4)
                self.assertGreaterEqual(upper, gross)
                self.assertLessEqual(upper, gross + 1)

    def test_clear_is_zero_but_untouched_slot_keeps_prestate(self):
        state = {A: {"state": {S: n.b.word(7), T: n.b.word(9)}}}
        delta = {"pre": {A: {"storage": {S: n.b.word(7)}}}, "post": {}}
        self.assertEqual(n.check_storage({A: {S: "0x0", T: "0x9"}}, state, delta), [])
        self.assertEqual(len(n.check_storage({A: {S: "0x7"}}, state, delta)), 1)

    def test_delta_preserves_untouched_storage_and_copies_input(self):
        state = {A: {"code": "0xab", "nonce": "0x1", "balance": "0x4", "state": {S: n.b.word(7), T: n.b.word(9)}}}
        delta = {"pre": {A: {"storage": {S: n.b.word(7)}}},
                 "post": {A: {"balance": "0x8", "nonce": 2}}}
        result = n.apply_delta(state, delta)
        self.assertEqual(result[A]["state"], {S: n.b.word(0), T: n.b.word(9)})
        self.assertEqual(result[A]["nonce"], "0x2")
        self.assertEqual(result[A]["balance"], "0x8")
        self.assertEqual(state[A]["state"][S], n.b.word(7))

    def test_missing_zero_slot_is_not_silently_accepted(self):
        self.assertEqual(n.missing_prestate({A: {"storage": {S: "0x0"}}}, {A: {"state": {}}}), [[A, S]])
        self.assertEqual(n.missing_prestate({A: {"storage": {S: "0x0"}}}, {A: {"state": {S: "0x0"}}}), [])

    def test_only_complete_world_dump_proves_unlisted_zero_storage(self):
        observed = {A: {"storage": {S: "0x0"}}}
        self.assertEqual(n.missing_prestate(observed, {}, complete=True), [])
        self.assertEqual(n.missing_prestate({A: {"storage": {S: "0x1"}}}, {}, complete=True), [[A, S]])
        before = n.dumped_storage({"alloc": {A[2:]: {"storage": {"0x1": "0x7"}}}})
        self.assertEqual(n.complete_storage_changes(before, {}), {A: {S: n.b.word(0)}})
        self.assertEqual(n.complete_storage_changes({}, before), {A: {S: n.b.word(7)}})

    def test_code_mismatch_is_detected(self):
        self.assertEqual(n.missing_prestate({A: {"code": "0xab"}}, {A: {"code": "0xcd"}}), [[A, "code"]])

    def test_miner_normalization_keeps_action_and_refuses_paid_cases(self):
        def log(action, gas, reward):
            return {"address": A, "topics": [n.MINER_WORK], "data": "0x" + "".join(f"{v:064x}" for v in (action, gas, reward))}
        self.assertEqual(n.events([log(3, 100, 0)]), n.events([log(3, 200, 0)]))
        self.assertNotEqual(n.events([log(3, 100, 0)]), n.events([log(4, 100, 0)]))
        with self.assertRaises(AssertionError): n.events([log(3, 100, 1)])

    def test_only_synthetic_transfer_annotation_is_removed(self):
        event = {"address": A, "topics": ["0x01"], "data": "0xab"}
        synthetic = {"address": "0xfffffffffffffffffffffffffffffffffffffffe", "topics": [], "data": "0x"}
        self.assertEqual(n.events([event, synthetic, event]), [(A, ["0x01"], "0xab")] * 2)

    def test_checkpoint_lanes_preserve_within_lane_order(self):
        a, b, c = (A, ["a"], "1"), (A, ["b"], "2"), (A, ["a"], "3")
        self.assertEqual(n.event_lanes([a, b, c]), n.event_lanes([a, c, b]))
        self.assertNotEqual(n.event_lanes([a, b, c]), n.event_lanes([c, a, b]))

    def test_growth_ranges_preserve_every_index_and_payout_across_checkpoints(self):
        def entry(first, count, payout=7):
            data = "0x" + "".join(f"{v:064x}" for v in (1, first, count, payout))
            return (A, [n.GROWTH_WINNERS_PAID, n.b.word(4)], data)
        self.assertEqual(n.event_lanes([entry(0, 32)]), n.event_lanes([entry(0, 12), entry(12, 20)]))
        self.assertNotEqual(n.event_lanes([entry(0, 32)]), n.event_lanes([entry(0, 12), entry(13, 20)]))
        self.assertNotEqual(n.event_lanes([entry(0, 32)]), n.event_lanes([entry(0, 32, 8)]))
        with self.assertRaises(AssertionError): n.event_lanes([entry(0, 33)])

    def test_worker_result_shape_is_exact(self):
        self.assertEqual(n.result_words("0x" + "".join(f"{v:064x}" for v in (1, 0, 32))), [1, 0, 32])
        with self.assertRaises(AssertionError): n.result_words("0x")


if __name__ == "__main__": unittest.main()
