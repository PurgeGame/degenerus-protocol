# Deferred Items — Phase 357

Out-of-scope discoveries logged during execution (NOT fixed in this phase).

## 357-00b

- **`test/unit/GovernanceGating.test.js` — `ADMIN-02 > multiple vault-owner-gated functions all check DGVE majority` is RED (pre-existing, out of scope).**
  At line ~247 the fixture calls `vault.connect(alice).gameSetAutoRebuy(true)`, but `gameSetAutoRebuy` does NOT exist on `DegenerusVault.sol` (renamed/removed in an earlier phase) → `TypeError: vault.connect(...).gameSetAutoRebuy is not a function`. This failure lives in the untouched `ADMIN-02` block (the 357-00b GATE-01..04 rewrite is at lines 446+); it is NOT caused by the soft-gate edit and exists independently at HEAD''. Hardhat tests are not part of the forge NON-WIDENING ledger (separate runner), so this does not affect the `live − union == ∅` gate. DEFERRED — fix the stale `gameSetAutoRebuy` reference (or drop the assertion) in a future Hardhat-fixture lane.

## 357-03 scope-boundary discovery (2026-06-03) — a FIFTH source commit landed AFTER the HEAD'''' freeze

While authoring `audit/FINDINGS-v56.0.md` (357-03, doc-only against the frozen audit subject HEAD'''' `77d8bc88`),
HEAD advanced to `c9b5d20d` ("refactor(passes): flat 10% pass lootbox + drop unreachable guards") — a NEW source
commit that mutates `DegenerusGame.sol` (+the whale module), landing AFTER the 357-00d reconciliation that froze
the subject at `77d8bc88`.

- This is OUTSIDE 357-03's scope (357-03 is the findings-authoring plan; it makes ZERO source edits — confirmed,
  the only working-tree change is the new `audit/FINDINGS-v56.0.md`).
- All upstream 357 artifacts (357-01-DELTA-AUDIT, 357-02-ADVERSARIAL-LOG, 357-00d-SUMMARY, STATE, ROADMAP) assert
  the audit subject is `77d8bc88` and `git diff 77d8bc88 HEAD -- <source>` is EMPTY. That invariant now FAILS by
  the two files in `c9b5d20d`.
- `audit/FINDINGS-v56.0.md` is authored CORRECTLY against the PLANNED subject `77d8bc88` (the `source_tree_frozen_ref`).
- NOT auto-fixed / NOT rolled back (Rule 4 + scope boundary — surface, do not self-heal). The new commit is either
  (a) the USER's separate in-flight change unrelated to this terminal, or (b) a FIFTH 357 contract gate that needs
  its own re-freeze + delta-audit/sweep reconciliation (the 357-00d pattern) BEFORE the 357-04 closure flip resolves
  the MILESTONE_V56_AT_HEAD_<sha> signal.
- ACTION FOR THE ORCHESTRATOR / 357-04: decide whether `c9b5d20d` is in-scope for v56.0. If yes, re-freeze the
  subject at `c9b5d20d`, run a 357-00d-style reconciliation (delta-audit §3.8 addendum + sweep + NON-WIDENING
  re-run + V56SubHardening/whale proofs), and update `source_tree_frozen_ref` + the §3.A/§5 anchors in
  FINDINGS-v56.0.md to the new HEAD. If no (separate change), the closure must pin the subject to `77d8bc88`
  explicitly (the signal's SHA != HEAD).
