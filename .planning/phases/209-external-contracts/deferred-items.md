# Deferred Items - Phase 209

## Pre-existing: DegenerusJackpots.sol lastBafResolvedDay type mismatch

- **File:** contracts/DegenerusJackpots.sol:648
- **Issue:** `lastBafResolvedDay` declared as `uint48` (line 131) but `getLastBafResolvedDay()` returns `uint32` (line 647). Compiler error: implicit conversion from uint48 to uint32.
- **Origin:** Phase 208-04 changed IDegenerusJackpots interface return type to uint32 but did not update the storage variable declaration.
- **Resolution:** DegenerusJackpots is likely covered by 209-03-PLAN.md (external contracts cascade).

## Pre-existing: test/ files with uint48 references

- **Files:** Multiple test/fuzz/*.t.sol files pass uint48 values to functions now expecting uint32.
- **Origin:** Phase 208 type narrowing cascade changed interfaces; test files not yet updated.
- **Resolution:** Test files are out of scope for type-narrowing plans (contract-only).
