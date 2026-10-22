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
            source = '''pragma solidity 0.8.38;
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

    def test_existing_helper_new_call_alias_using_and_imported_body_are_pinned(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'contracts').mkdir()
            (root / 'node_modules').mkdir()
            (root / 'node_modules/Payout.sol').write_text('''pragma solidity 0.8.38;
library Payout {
 function pay(address payable recipient, uint amount) internal { recipient.transfer(amount); }
}''')
            source = '''pragma solidity 0.8.38;
import {Payout as Alias} from "Payout.sol";
contract Calls {
 using Alias for address payable;
 function _payout(address payable to) private { to.pay(1); }
 function _relay(address payable to) internal { _payout(to); }
 function existing(address payable to) external { _relay(to); }
 function added(address payable to) external { PLACEHOLDER }
}'''
            file = root / 'contracts/Calls.sol'
            file.write_text(source.replace('PLACEHOLDER', ''))
            expected = gate.discover(root)
            self.assertTrue(any(k[0] == 'Payout.sol' and k[2] == 'opcode-or-value' for k in expected))
            self.assertTrue(any(k[2] == 'recipient-helper' and k[3] == 'to.pay(1)' for k in expected))
            self.assertTrue(any(k[2] == 'recipient-helper' and k[3] == '_relay(to)' for k in expected))
            file.write_text(source.replace('PLACEHOLDER', '_relay(to);'))
            current = gate.discover(root)
            self.assertNotEqual(current, expected, 'a new call to the existing payout helper fails the manifest equality gate')
            self.assertEqual(sum((current - expected).values()), 1)

    def test_internal_virtual_override_and_pointer_routes_are_transitive(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'contracts').mkdir()
            (root / 'node_modules').mkdir()
            source = '''pragma solidity 0.8.38;
contract Base {
 function payout(address payable to) internal virtual {}
 function relay(address payable to) external { payout(to); }
}
contract Child is Base {
 function payout(address payable to) internal override { to.transfer(1); }
 function indirect(address payable to) external {
  function(address payable) internal fn = payout;
  fn(to);
 }
}'''
            (root / 'contracts/Calls.sol').write_text(source)
            sites = gate.discover(root)
            self.assertTrue(any(k[1] == 'Base.relay' and k[2] == 'recipient-helper' for k in sites))
            self.assertTrue(any(k[3] == 'fn(to)' and k[2] == 'recipient-helper' for k in sites))

    def test_view_helper_through_a_wider_pointer_is_transitive(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'contracts').mkdir()
            (root / 'node_modules').mkdir()
            source = '''pragma solidity 0.8.38;
interface Oracle { function price() external view returns (uint); }
contract Calls {
 Oracle oracle;
 function read() internal view returns (uint) { return oracle.price(); }
 function run() external returns (uint) {
  function() internal returns (uint) p = read;
  return p();
 }
}'''
            (root / 'contracts/Calls.sol').write_text(source)
            sites = gate.discover(root)
            self.assertTrue(any(k[3] == 'p()' and k[2] == 'recipient-helper' for k in sites))

    def test_overloaded_callers_are_distinct_sites(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'contracts').mkdir()
            (root / 'node_modules').mkdir()
            source = '''pragma solidity 0.8.38;
contract Calls {
 function _pay(address payable to) private { to.transfer(1); }
 function run(address payable to) external { FIRST }
 function run(address payable to, uint) external { SECOND }
}'''
            file = root / 'contracts/Calls.sol'
            file.write_text(source.replace('FIRST', '_pay(to);').replace('SECOND', ''))
            expected = gate.discover(root)
            file.write_text(source.replace('FIRST', '').replace('SECOND', '_pay(to);'))
            self.assertNotEqual(expected, gate.discover(root))

    def test_bounded_wrapper_alias_and_using_match_referenced_declaration(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'contracts/libraries').mkdir(parents=True)
            (root / 'node_modules').mkdir()
            (root / 'contracts/libraries/BoundedCall.sol').write_text('''pragma solidity 0.8.38;
library BoundedCall {
 function staticWord(address target) internal view returns (bool ok) {
  (ok,) = target.staticcall("");
 }
}''')
            (root / 'contracts/Calls.sol').write_text('''pragma solidity 0.8.38;
import {BoundedCall as Renamed} from "./libraries/BoundedCall.sol";
contract Calls {
 using Renamed for address;
 function run(address target) external view { Renamed.staticWord(target); target.staticWord(); }
}''')
            sites = gate.discover(root)
            self.assertEqual(sum(n for k,n in sites.items() if k[2] == 'bounded-wrapper'), 2)

if __name__ == '__main__':
    unittest.main()
