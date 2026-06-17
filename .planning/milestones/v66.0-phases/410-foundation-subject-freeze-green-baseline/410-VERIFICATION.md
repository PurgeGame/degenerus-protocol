---
phase: 410
status: passed
verified: 2026-06-16
requirements: [FOUND-01, FOUND-02]
---

# Phase 410 Verification — FOUNDATION

**Status: PASSED** (2/2 must-haves verified)

## Success Criteria

1. ✅ **Subject byte-frozen with commit + tree hash recorded.** Subject = contract commit `42c8e9c6`,
   `contracts/` tree `0dd445a64cfe7e096427d44f058c40abb1233b5f`. `git diff 42c8e9c6 -- contracts/` empty;
   doc commits on top do not touch `contracts/` (verified tree-equal at HEAD).
2. ✅ **Green baseline oracle captured + documented.** Forge `889/0/110` (identical to v65 → 0 regressions);
   hardhat `1232 passing / 136 failing / 14 pending`. Recorded in `410-FOUNDATION.md` with the
   regression-detection rule.
3. ✅ **Pre-existing reds catalogued as carried-not-new.** The 136 hardhat failures match the known carried
   floor; none are curse/smite/decurse/CurseChanged; the CurseChanged emit is proven inert across both nets
   (forge identical, hardhat 0 new, 42/42 curse suite green, EIP-170 OK).

## Notes

- The one pre-freeze contract change (USER-approved CurseChanged indexer-parity emit, `42c8e9c6`) is folded
  into the frozen subject so the audit covers shipping bytecode.
- Tracked carried items that become later v66 work: the `vm.skip`'d mid-day lootbox binding test → MECH-02.

No human verification required. Proceed to Phase 411 (RNGNET).
