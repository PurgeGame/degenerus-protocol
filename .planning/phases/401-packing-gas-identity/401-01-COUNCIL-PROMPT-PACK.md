# Storage-Packing & Gas-Identity Correctness Review — Degenerus Protocol (cross-model council, NET-1)

Review the storage-packing and gas-refactor changes for behavior-identity and storage-layout safety. Frozen subject: the `contracts/` tree at this checkout (read-only; do not modify any file). The authoritative storage layout is whatever `forge inspect <Contract> storageLayout` reports — derive bounds against that, not against comments. Report any divergence with `file:line`, the invariant vs the code, and the concrete effect. A clean result is a valid outcome.

## The invariants to verify

- **PACK-01 — narrowing safety.** Every narrowed packed field's declared width must be ≥ its real-world maximum value — no silent truncating cast can ever lose a high bit. Enumerate each narrowing with the bound that makes it safe, across: the DegenerusGame 6-slot merge, the StakedDegenerusStonk solvency scalars + `poolBalances`, BurnieCoinflip (the 8-bit 3-state day-result + lossless-wei stake), and the DegenerusAdmin vote-record. For each field, state the type width, the maximum value it can hold (derive from the writers + caps), and confirm width ≥ max. Flag any field whose max can exceed its width (a real truncation), or any narrowing cast (`uintN(x)`) that can wrap.
- **PACK-02 — masked RMW + slot agreement.** Every masked read-modify-write helper (set one packed field, preserve the co-residents) must clear exactly its own bits and preserve every co-resident field. Where a packed slot is read/written across modules via delegatecall (shared storage context), all readers and writers must use IDENTICAL shift/mask/offset conventions (slot agreement by construction). Find any RMW that clobbers a co-resident, any shift/mask mismatch between a writer and a reader of the same slot, or any field offset that two modules disagree on.
- **PACK-03 — dispatch + gas hot-path identity.** The raw `delegatecall(msg.data)` dispatch and the gas-round hot-path refactors must resolve the same function selector, ABI-decode identically, and change NO externally-observable behavior (return data, revert behavior/selector, emitted events). Find any refactor that diverges in output, revert, event, or selector routing.
- **PACK-04 — ABI getter preservation.** Every field that was privatized or packed must still have an external ABI getter with the same signature/return shape, so no off-chain consumer (especially the indexer) breaks. Find any field whose public getter was removed or whose return type/shape silently changed.

## Focus questions (highest value)

1. **Silent truncation:** is there ANY narrowing cast or packed field whose maximum reachable value (from the writers + the protocol caps) exceeds its bit-width? Walk the widest writer for each narrowed field.
2. **Co-resident clobber:** does any single-field setter write the full slot (or a wrong mask) and zero a co-resident? Check the masked-RMW helpers field-by-field.
3. **Cross-module slot disagreement:** for each delegatecall-shared packed slot, do the Game and the module(s) that read/write it agree on every field's offset, width, and mask?
4. **Dispatch divergence:** does the raw `delegatecall(msg.data)` (and any selector/ABI-decode refactor) route + decode identically to the prior explicit dispatch — same selector, same revert bubbling, same return data?
5. **Getter/interface break:** was any externally-read getter (incl. indexer-consumed views/events) removed or reshaped by the privatization/packing?

PRIOR CONTEXT (carried — re-verify, don't re-litigate): the v61 packing moved storage slots region-dependently (subs −3, lootbox/degenerette −2, mint/rng −1, slot-0 fields −2, `balancesPacked` root unmoved @7); the v64 packing rounds further narrowed fields (Admin, BurnieCoinflip 8-bit day-result + lossless-wei stake, caps). The FOUNDATION phase (397) already re-derived the authoritative layout and reconciled the slot-hardcoded harnesses to a GREEN baseline — so the layout is internally consistent; this review checks the NARROWING widths, the masked RMW, the dispatch identity, and the getters.

Report each invariant with `file:line` + a verdict (holds / diverges), and list any divergence as a finding with the concrete effect (truncation value-loss / co-resident clobber / behavior divergence / interface break).
