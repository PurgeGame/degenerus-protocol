# Phase 482 — Deferred Items

## D-482-ORACLE-01 (pre-existing, out-of-scope) — storage-layout oracle WWXRP name mismatch

- **What:** `scripts/layout/storage_layout_oracle.sh` lists `WrappedWrappedXRP` in its `CONTRACTS`
  array (line 29) and ships a golden `scripts/layout/golden/WrappedWrappedXRP.json`, but the contract
  was renamed to `WWXRP` (`contracts/WWXRP.sol`, `contract WWXRP {`). `forge inspect WrappedWrappedXRP
  storageLayout` errors "No contract found with the name `WrappedWrappedXRP`", so the oracle reports a
  spurious "STORAGE LAYOUT CHANGED for WrappedWrappedXRP" (live inspect empty → whole golden diffs out).
- **Why deferred:** PRE-EXISTING (predates 480/481/482; `WWXRP.sol` is unmodified in the working tree)
  and unrelated to the Degenerette repack. SCOPE BOUNDARY — not caused by this task.
- **The 482-relevant proof is unaffected:** `DegenerusGameDegeneretteModule` layout is byte-identical to
  its golden (`degeneretteBets` stays slot 38, type unchanged), and the delegatecall shared-slot
  consistency (modules vs Game) is OK.
- **Fix (when picked up):** in `storage_layout_oracle.sh` rename the `WrappedWrappedXRP` entry → `WWXRP`,
  then `storage_layout_oracle.sh --capture` to rewrite the golden under the correct name (or `git mv` the
  golden). Verify the oracle goes fully green. Candidate for the 484 verify/close pass.
