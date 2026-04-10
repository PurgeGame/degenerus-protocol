---
phase: 211-test-suite-repair
plan: 02
subsystem: testing
tags: [foundry, storage-layout, vm-load, vm-store, bit-shifts]

requires:
  - phase: 210-test-compilation-repair
    provides: "Compilable test files with correct types (uint8->bool, uint48->uint32)"
provides:
  - "TicketLifecycle.t.sol with v24.1 slot constants, bit shifts, and ticketWriteSlot read from slot 0"
  - "StorageFoundation.t.sol with v24.1 field placement assertions and slot 11 for prizePoolPendingPacked"
affects: [211-test-suite-repair]

tech-stack:
  added: []
  patterns: ["v24.1 storage layout constants for vm.load/vm.store test helpers"]

key-files:
  created: []
  modified:
    - test/fuzz/TicketLifecycle.t.sol
    - test/fuzz/StorageFoundation.t.sol

key-decisions:
  - "No decisions needed -- all changes mechanical per v24.1 layout"

patterns-established:
  - "Slot 0 packed field access: use bit shifts 112 (level), 136 (jackpotPhase), 144 (jackpotCounter), 168 (rngLocked), 200 (compressedFlag), 224 (ticketWriteSlot)"

requirements-completed: [VER-02]

duration: 3min
completed: 2026-04-10
---

# Phase 211 Plan 02: Storage Constant Repair Summary

**Fixed 22+ hardcoded slot constants and bit shifts in TicketLifecycle.t.sol and 2 field placement assertions in StorageFoundation.t.sol to match v24.1 storage layout**

## Performance

- **Duration:** 3 min
- **Started:** 2026-04-10T17:07:01Z
- **Completed:** 2026-04-10T17:10:27Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Updated all slot constants in TicketLifecycle (TICKET_QUEUE_SLOT 13->12, TICKETS_OWED_PACKED_SLOT 14->13, lootboxRngIndex 40->38, lootboxRngWordByIndex 44->39)
- Updated all bit shift constants (LEVEL_SHIFT 144->112, JACKPOT_PHASE_SHIFT 168->136, JACKPOT_COUNTER_SHIFT 176->144, RNG_LOCKED_SHIFT 200->168, COMPRESSED_FLAG_SHIFT 232->200, WRITE_SLOT_SHIFT 48->224)
- Moved _getWriteSlot() from SLOT_1 to SLOT_0 (ticketWriteSlot now in slot 0 byte 28)
- Fixed StorageFoundation field offset assertions: ticketWriteSlot/prizePoolFrozen/ticketsFullyProcessed all in slot 0, prizePoolPendingPacked at slot 11

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix TicketLifecycle.t.sol slot constants, bit shifts, and ticketWriteSlot read** - `24ab9693` (fix)
2. **Task 2: Fix StorageFoundation.t.sol field placement and slot assertions** - `4793a854` (fix)

## Files Created/Modified
- `test/fuzz/TicketLifecycle.t.sol` - Updated slot constants, bit shifts, lootbox slots, _getWriteSlot helper, and all inline comments
- `test/fuzz/StorageFoundation.t.sol` - Updated field offset assertions (slot 0 for all bool fields), prizePoolPendingPacked slot 12->11

## Decisions Made
None - followed plan as specified.

## Deviations from Plan
None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Both files compile cleanly with `forge build --skip FuturepoolSkim`
- Ready for runtime test execution in Plan 04 (test suite verification)

---
*Phase: 211-test-suite-repair*
*Completed: 2026-04-10*
