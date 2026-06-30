# Phase 480 — Deferred / out-of-scope items (480-01 Tasks 1+2 · 480-02 Task 2)

Pre-existing conditions surfaced during the rename-sweep execution. None are caused by the
ticket→entry rename; all are logged here per the scope boundary (do NOT fix pre-existing
failures in unrelated surfaces inside this rename phase).

## 0. `forge test` full-run blocked by foundry-1.6.0-nightly (480-02) — environmental, NOT the rename

- Full `forge test` on this machine reports `223 passed / 116 failed / 339 total` in ~1.2s; every
  failure is `panic: arithmetic underflow or overflow (0x11)` in `setUp()` for full-game-deploy
  suites. The `-vvvvv` trace shows `setUp` runs `vm.warp(86400)`, deploys all 17 modules, then the
  final genesis CREATE (the `DegenerusGame` facade constructor) underflows — `vm.warp` does not
  propagate to that nested CREATE under `forge 1.6.0-nightly`. This is the issue `foundry.toml:23-28`
  documents ("protocol constructor's day-arithmetic ... panics (0x11)") + the `AutoOpenCursorRing.t.sol`
  "Foundry block.timestamp caching workaround".
- Proof it is NOT the contract / rename: `npm test` (Hardhat) deploys the SAME post-480 contracts at
  the SAME fixed timestamp 86400 and plays the full game — 1362 passing, 0 failing. The forge-failing
  test files are byte-identical to the 479-close (where `forge test` was 1003/0/107), and the rename is
  byte-neutral. Every forge suite passes in isolation / small batches; only full-game-deploy suites
  hit the nightly flake.
- Recommended fix (owner/tooling call, out of this rename's scope): run `forge test` on the repo's
  expected stable foundry (CI installs it via `foundry-toolchain@v1`); `foundryup` to the stable line,
  then `forge test` reproduces the 1003/0/107 floor. No code change required.

## 1. Stale layout-oracle entry: `WrappedWrappedXRP` (pre-existing)

- `scripts/layout/storage_layout_oracle.sh` lists `WrappedWrappedXRP` in its standalone
  `CONTRACTS` array, and `scripts/layout/golden/WrappedWrappedXRP.json` (4 slots) still exists.
- The contract file was renamed `contracts/WrappedWrappedXRP.sol` → `contracts/WWXRP.sol` in
  commit `aa74de08` ("named errors, WWXRP rename, ..."), BEFORE this phase. The oracle's
  contract list + golden filename were never updated.
- Effect: `forge inspect WrappedWrappedXRP storageLayout` → "No contract found", so
  `--capture` writes an empty golden and `--check` reports
  `STORAGE LAYOUT CHANGED for WrappedWrappedXRP`. This has been red since `aa74de08`.
- This phase did NOT touch `WWXRP.sol`; the rename is provably layout-clean on every other
  golden. The stale `WrappedWrappedXRP.json` was restored to its baseline (not committed empty).
- Recommended 1-line fix (out of this rename's scope — owner/oracle-maintainer call):
  in `storage_layout_oracle.sh` change `WrappedWrappedXRP` → `WWXRP` in the `CONTRACTS` array,
  then `git mv scripts/layout/golden/WrappedWrappedXRP.json scripts/layout/golden/WWXRP.json`
  and re-run `--capture`. After that, `--check` is green.

## 2. Pre-existing golden staleness corrected by the required recapture

The baseline goldens at HEAD (`4ab900f1`) were missing two already-committed storage variables:
- `_sdgnrsBonusLevel` (uint24, slot 58 / offset 25 — packed into existing free space)
- `deityRecipientBoonCount` (mapping(address=>mapping(address=>uint8)), slot 65 — appended)

Both are present in `contracts/storage/DegenerusGameStorage.sol` at HEAD (lines 2441 / 2526) but
absent from the HEAD goldens — i.e. a prior storage addition never recaptured. The Task-2(b)
recapture (required for `--check` to match live layout) necessarily picks them up. They are
append-only (no existing slot/offset/bytes/encoding moved), so they do NOT represent a layout
change introduced by the ticket→entry rename. Documented here so the golden diff's non-
label/typeLabel additions are not mistaken for a rename-induced layout move.
