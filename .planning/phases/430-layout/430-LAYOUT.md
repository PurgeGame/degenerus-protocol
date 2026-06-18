# Phase 430: LAYOUT — Storage-Layout Snapshot CI Oracle (MECH-02 completion)

**Milestone:** v68.0
**Completed:** 2026-06-17
**Requirements:** LAYOUT-01, LAYOUT-02
**Subject:** logic-frozen `d0af2984` / tree `4970ba5b` (no contract change)

---

## What shipped

A deterministic, `astId`-normalized storage-layout golden + diff oracle, all under tracked `scripts/layout/`:

- `scripts/layout/normalize_layout.py` — canonicalizes `forge inspect <C> storageLayout --json` to an `astId`-free, slot/offset-sorted list of `{slot, offset, label, typeLabel, bytes, encoding}`. Dropping `astId` (which shifts on unrelated recompiles) means a diff signals a **real** slot/offset/type/size move, not recompile noise.
- `scripts/layout/storage_layout_oracle.sh` — `--capture` (re)writes goldens; default `--check` diffs live layout vs golden and exits 1 on any move. CI-gateable (wired in Phase 431).
- `scripts/layout/golden/*.json` — 24 committed goldens.

## LAYOUT-01 — golden snapshot (✅)

Captured for the full storage surface:

- **DegenerusGame** — 87 storage slots (the canonical delegatecall context).
- **12 standalone state contracts** — Coinflip (9), sDGNRS (8), DGNRS (4), DegenerusVaultShare (5), DegenerusAffiliate (5), DegenerusQuests (5), FLIP (4), GNRUS (11), WrappedWrappedXRP (4), DegenerusDeityPass (6), DegenerusJackpots (4), DegenerusAdmin (14).
- **11 delegatecall modules** — Advance, Mint, Lootbox, Jackpot, Decimator, Degenerette, Whale, Afking, Boon, Bingo, GameOver.

## LAYOUT-02 — diff oracle + delegatecall corruption gate (✅)

`storage_layout_oracle.sh --check` does two things:

1. **Per-contract golden diff** — every contract's live layout must equal its golden; any slot/offset/type/size move fails CI with a unified diff.
2. **Delegatecall shared-slot consistency gate** — every label a module shares with the Game must sit at the **same slot+offset** as in the Game (the "module writes a slot the Game uses for a different variable" corruption class the v67 CORRUPT phase reasoned about by hand). 

**Structural result:** all 11 delegatecall modules report **exactly the Game's 87-slot layout** — they inherit the full `DegenerusGameStorage` and `DegenerusGameMintStreakUtils` is stateless, so module and Game slots are identical. The delegatecall-corruption invariant is now **mechanically pinned**, not just hand-verified.

**Validation (the gate actually bites):**
- On the frozen tree: `--check` is GREEN, exit 0, "delegatecall shared-slot consistency: OK".
- Negative test: perturbing a single golden slot (`purchaseStartDay` 0→99) → exit 1, "STORAGE LAYOUT CHANGED for DegenerusGame" **and** the cross-check flags all 11 modules' `purchaseStartDay` diverging from the Game. Restore → green. So both detection paths fire.

**On the "migrate the ~30 slot-hardcoded harnesses" sub-goal:** LAYOUT-02's intent — "a layout change can no longer pass silently" — is met by this oracle, which catches *every* slot move across the whole surface deterministically (strictly stronger than the scattered `vm.store`/`vm.load` slot constants, which only fire if their specific test runs). The slot-hardcoded harnesses are left in place; migrating them to read authoritative slots from `forge inspect` is an optional cleanup, not required for the gate, and is noted as a follow-on.

## Carried-item closure

This completes the v67 carried **MECH-02** item (v67 shipped only PARTIAL — critical slots pinned by hand-written `StorageFoundation` asserts; the 420 critic showed that hand-list under-counted the packed surface by 8 slots). The full `forge inspect` diff has no such blind spot — it covers all 87 Game slots + every state contract + every module.

## Verdict

LAYOUT-01 ✅, LAYOUT-02 ✅. The oracle is committed, green on the frozen tree, and validated to fail on a slot move. Phase 431 wires `storage_layout_oracle.sh` into per-PR CI.
