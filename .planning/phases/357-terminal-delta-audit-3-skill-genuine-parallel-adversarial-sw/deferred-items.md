# Deferred Items — Phase 357

Out-of-scope discoveries logged during execution (NOT fixed in this phase).

## 357-00b

- **`test/unit/GovernanceGating.test.js` — `ADMIN-02 > multiple vault-owner-gated functions all check DGVE majority` is RED (pre-existing, out of scope).**
  At line ~247 the fixture calls `vault.connect(alice).gameSetAutoRebuy(true)`, but `gameSetAutoRebuy` does NOT exist on `DegenerusVault.sol` (renamed/removed in an earlier phase) → `TypeError: vault.connect(...).gameSetAutoRebuy is not a function`. This failure lives in the untouched `ADMIN-02` block (the 357-00b GATE-01..04 rewrite is at lines 446+); it is NOT caused by the soft-gate edit and exists independently at HEAD''. Hardhat tests are not part of the forge NON-WIDENING ledger (separate runner), so this does not affect the `live − union == ∅` gate. DEFERRED — fix the stale `gameSetAutoRebuy` reference (or drop the assertion) in a future Hardhat-fixture lane.
