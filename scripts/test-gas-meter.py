#!/usr/bin/env python3
"""Falsifiability checks for the checkpoint-aware gas-read drift gate."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
from check_gas_meter import scan_source


class GasMeterGateTest(unittest.TestCase):
    def test_comments_and_strings_are_not_reads(self):
        reads, bad = scan_source("Example.sol", '''contract X {
          // gasleft() block.timestamp
          function f() external pure { string memory s = "gasleft()"; }
        }''')
        self.assertFalse(reads)
        self.assertFalse(bad)

    def test_solidity_and_assembly_gas_reads_are_scoped(self):
        reads, _ = scan_source("Example.sol", '''contract X {
          function f() external view returns (uint256) {
            return gasleft();
          }
          function g() external view returns (uint256 x) {
            assembly { x := gas() }
          }
        }''')
        self.assertEqual(sum(reads.values()), 2)
        self.assertEqual({key[1] for key in reads}, {"f", "g"})

    def test_ambient_input_in_ticket_entropy_is_rejected(self):
        for expression in ("block.timestamp", "msg.sender", "tx.origin", "blockhash(1)"):
            with self.subTest(expression=expression):
                _, bad = scan_source("libraries/TicketEntropy.sol", f'''library T {{
                  function f() internal view {{
                    uint256 x = uint256({expression});
                  }}
                }}''')
                self.assertEqual(len(bad), 1)

    def test_additional_read_changes_pinned_statement(self):
        original, _ = scan_source("Example.sol", '''contract X {
          function f() external view { uint256 x = gasleft(); }
        }''')
        mutated, _ = scan_source("Example.sol", '''contract X {
          function f() external view { uint256 x = gasleft() ^ gasleft(); }
        }''')
        self.assertTrue(mutated - original)

    def test_identity_auth_guard_does_not_exempt_other_ambient_inputs(self):
        source = '''contract T {
          function registerAffiliateOwner(address owner, bool required) external {
            if (msg.sender != ContractAddresses.AFFILIATE) revert E();
          }
        }'''
        path = "modules/DegenerusGameTicketModule.sol"
        _, bad = scan_source(path, source)
        self.assertFalse(bad)
        for mutation in (
            "if (msg.sender != ContractAddresses.VAULT) revert E();",
            "if (msg.sender != ContractAddresses.AFFILIATE) revert E(); uint256 x = block.timestamp;",
            "uint256 x = uint160(msg.sender);",
        ):
            _, bad = scan_source(path, source.replace(
                "if (msg.sender != ContractAddresses.AFFILIATE) revert E();", mutation))
            self.assertEqual(len(bad), 1)


if __name__ == "__main__":
    unittest.main()
