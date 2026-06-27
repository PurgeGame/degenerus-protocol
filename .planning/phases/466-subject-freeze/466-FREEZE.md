# Phase 466 — SUBJECT-FREEZE-CONFIRM

**Milestone:** v74.0 — As-Built Milestone Audit + C4A Package
**Executed:** 2026-06-26
**Gate:** none

Byte-freezes the audit subject at HEAD `3986926c`, resolves the 2 dirty liveness test
files, captures the storage-layout golden vs v73, and defines the closure baseline.

---

## SUBJ-01 — contracts/ clean at the frozen subject ✓

- HEAD commit `5b7b5503` ("docs: supersede stale v74 plan…") touches **0 contract files**
  (7 files changed, all `.planning/` + the 2 test files); it sits on impl commit
  `3986926c` ("sDGNRS level lootbox + pre-deploy hardening batch").
- **Frozen `contracts/` tree = `280bdb19dc071ad20c5ddabbf57ccd7929a7589b`**, identical at
  HEAD and at `3986926c` (the docs commit did not touch contracts).
- `git diff HEAD -- contracts/` is **empty** (working tree == HEAD contracts).
- Distinct from the v73.0 frozen tree `d6615306` (`v73.0:contracts`), confirming the
  `v73.0 → HEAD` contract batch is real (the +1861/−1030 diff).

**Subject of record:** `contracts/` tree `280bdb19` · impl commit `3986926c` · on `main`,
local HEAD `5b7b5503`, not pushed (push separately gated, not required for the audit).

## SUBJ-02 — 2 dirty liveness test files resolved ✓

`test/edge/LivenessMidJackpot.test.js` (+199/−105) and
`test/edge/LivenessProductivePause.test.js` (+152/−…) were carried dirty. The edits are
legitimate rewrites aligning the tests to the as-built liveness model — the day-clock pause
replaced by the phase-independent `_vrfDeadmanFired()` (`simulatedDayIndex - dailyIdx > 120`).
They read `dailyIdx` (slot 0, byte offset 3, uint24) straight from storage to land the warp
exactly on the 120-day deadman threshold, then drive `advanceGame` to game-over.

**Verified green before commit:** `npx hardhat test … LivenessMidJackpot LivenessProductivePause`
→ **11 passing (30s)**. (The trailing mocha `file-unloader` "Cannot find module" line is a
known relative-path teardown quirk that fires *after* all tests pass — not a failure.)

Test-only (not part of the contract subject) → **committed** this phase, clearing the working
tree so the freeze is unambiguous.

⚠ Harness note for 467: a plain `hardhat test` run regenerates `contracts/ContractAddresses.sol`
(auto-generated deploy-address file, exempt from the contract subject). It was restored to the
frozen hash `cb70d99e141d41cc68cc2d88bfb9075d3560f4e9` after the run; restore it after every
Hardhat run during the milestone.

## SUBJ-03 — storage-layout golden vs v73 ✓

`forge inspect DegenerusGame storageLayout` captured at HEAD
(`storage-HEAD-DegenerusGame.json`) and at v73.0 (`storage-v73-DegenerusGame.json`, built in a
detached worktree at the `v73.0` tag). astId-normalized top-level diff:

- **Top-level slot/offset moves v73 → HEAD: NONE.**
- **Added (1):** `_sdgnrsBonusLevel` — `t_uint24` at **slot 58, offset 25** (packed into the
  free tail of the cursor slot; no downstream slot displaced).
- **Removed (top-level): none.**
- The one "type change" flagged (same slot/offset) is `vrfCoordinator`
  `IVRFCoordinator` astId `7313 → 33011` — a recompile astId bump, not a layout change.
- `_subOf` stays **slot 54**; `boxPlayers` stays **slot 59**;
  `BitPackingLib.WHALE_PASS_TYPE_SHIFT` stays **bit 152** (`BitPackingLib.sol:70`).

**`Sub` struct within-slot repack (`reinvestPct` removal)** — authoritative per-member table
(supersedes the "48→40 bits" shorthand in WIRE-01; the real change is a uint8 removal → 8-bit
down-shift of every following field; struct shrinks 32→31 bytes, still one slot):

| member | v73 slot/off | HEAD slot/off |
|---|---|---|
| dailyQuantity | 0/0 | 0/0 |
| validThroughLevel | 0/1 | 0/1 |
| **reinvestPct (uint8)** | **0/4** | **REMOVED** |
| flags | 0/5 | 0/4 |
| score | 0/6 | 0/5 |
| amount | 0/8 | 0/7 |
| lastAutoBoughtDay | 0/11 | 0/10 |
| lastOpenedDay | 0/14 | 0/13 |
| afkCoveredThroughDay | 0/17 | 0/16 |
| afkingStartDay | 0/20 | 0/19 |
| affiliateBase | 0/23 | 0/22 |
| pendingFlip | 0/27 | 0/26 |
| subStreakLatch | 0/30 | 0/29 |

(Goldens for the other state contracts + the per-module shared-layout consistency gate are
re-captured/re-validated in 467/472; the existing `scripts/layout/golden/` set is v71-era
`86515d27` and its `CONTRACTS=(…)` list still names `WrappedWrappedXRP` — a 467 test-infra fix.)

## SUBJ-04 — closure baseline + push posture ✓

- Closure baseline name reserved: **`MILESTONE_V74_AT_HEAD_<sha>`**, pinned to the frozen
  `contracts/` tree `280bdb19` / impl `3986926c`. Distinct from the stale v73 pin
  `MILESTONE_V73_AT_HEAD_15650b6a…` (tree `d6615306`). The concrete `<sha>` is emitted at
  Phase 478 (the terminal commit), since `.planning/`/`test/`/`audit/` commits land during the
  milestone without touching the frozen contract tree.
- **Push posture:** local HEAD is the subject; push is **not required** for the audit and stays
  separately gated.

---

**Verdict:** subject byte-frozen and confirmed. No top-level slot move vs v73; the only layout
deltas are the documented `Sub` `reinvestPct` within-slot repack and the additive
`_sdgnrsBonusLevel`. Proceed to 467 (harness-green gate).
