import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('recipient_calls', ROOT / 'scripts/check-recipient-calls.py')
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)

class RecipientCallsTest(unittest.TestCase):
    def test_literal_payload_is_not_normalized_as_comment_or_whitespace(self):
        original = 'recipient.call( "x  // y" /* note */ )'
        normalized = gate.normalize_expression(original)
        self.assertIn('"x  // y"', normalized)
        self.assertNotIn('note', normalized)
        self.assertNotEqual(normalized, gate.normalize_expression('recipient.call("x // y")'))

    def test_new_recipient_routes_and_multiplicity_are_detected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'contracts').mkdir()
            (root / 'node_modules').mkdir()
            source = '''pragma solidity >=0.8.26 <0.9.0;
interface Receiver { function arbitraryHook() external; }
contract Calls {
 address payable stored;
 function() external pointer;
 function run() external {
  stored.call(""); stored.call("");
  stored.send(1); stored.transfer(1);
  Receiver(stored).arbitraryHook(); pointer();
  assembly { pop(call(1000, 1, 1, 0, 0, 0, 0)) }
 }
 // stored.call(""); Receiver(stored).arbitraryHook();
 function text() external pure returns(string memory) { return "stored.call()"; }
}'''
            file = root / 'contracts/Calls.sol'
            file.write_text(source)
            sites = gate.discover(root)
            self.assertEqual(sum(sites.values()), 7)
            self.assertEqual(next(n for k, n in sites.items() if k[3] == 'stored.call("")'), 2)
            self.assertTrue(any(k[2] == 'external' and k[3] == 'pointer()' for k in sites))
            file.write_text(source.replace('stored.call(""); stored.call("");', 'stored.call("");'))
            changed = gate.discover(root)
            self.assertEqual(sum((sites - changed).values()), 1)
            self.assertNotEqual(sites, changed)

if __name__ == '__main__':
    unittest.main()
