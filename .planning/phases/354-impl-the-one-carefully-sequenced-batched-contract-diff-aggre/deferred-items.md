# Phase 354 — Deferred / Out-of-Scope Items

Items discovered during execution that are NOT caused by the current plan's changes.
Per the executor SCOPE BOUNDARY rule: logged, NOT fixed.

## 354-02

- **`forge build` lint warning (`unsafe-typecast`) — `contracts/modules/DegenerusGameMintModule.sol:1704`**
  - `stampDay != 0 && uint24(day) > stampDay + LOOTBOX_BOOST_EXPIRY_DAYS` — `uint24(day)` truncation lint.
  - PRE-EXISTING, in a file NOT touched by 354-02 (this plan edits only `contracts/DegenerusQuests.sol` + `contracts/interfaces/IDegenerusQuests.sol`).
  - `forge build` exits 0 (lint informational only; not a compile error). Out of scope; left untouched.
