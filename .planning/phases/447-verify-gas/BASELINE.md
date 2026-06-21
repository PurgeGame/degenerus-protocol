# v72.0 green baseline (447 VERIFY+GAS)

- Subject: ffbd7796 (v70 freeze) → HEAD 16225de6 working tree (uncommitted gas edits will land on top).
- `forge build`: clean (rc=0; one forge-lint unsafe-typecast warning, lint-suppressed).
- `forge test`: **944 passed / 0 failed / 108 skipped** (1052 total), 136 suites, ~66s wall.
- Captured 2026-06-21 at v72 init. This is the reference the FREEZE diff must still hold (≥944/0).
- NOTE: `npm test` (Hardhat/JS) is the known-blocked harness (GAME_FOILPACK_MODULE/ContractAddresses gap) → repaired in phase 449 TST.
