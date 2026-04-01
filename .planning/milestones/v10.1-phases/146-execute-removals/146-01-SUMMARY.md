---
phase: 146-execute-removals
plan: 01
subsystem: contracts
tags: [solidity, access-control, abi-cleanup, burnie-coinflip, forwarding-wrappers]

requires:
  - phase: 145-candidate-review
    provides: Approved removal list for 7 BurnieCoin forwarding wrappers
provides:
  - BurnieCoinflip.onlyFlipCreditors expanded to accept GAME, BURNIE, AFFILIATE, ADMIN
  - All creditFlip/creditFlipBatch calls route directly to BurnieCoinflip
  - IDegenerusCoinModule stripped of creditFlip/creditFlipBatch
  - 7 forwarding wrappers deleted from BurnieCoin ABI
affects: [146-execute-removals plan 02, test-suite, deployment]

tech-stack:
  added: []
  patterns: [direct-call-pattern for coinflip crediting instead of forwarding through BurnieCoin]

key-files:
  created: []
  modified:
    - contracts/BurnieCoinflip.sol
    - contracts/BurnieCoin.sol
    - contracts/DegenerusGame.sol
    - contracts/DegenerusAdmin.sol
    - contracts/DegenerusAffiliate.sol
    - contracts/interfaces/DegenerusGameModuleInterfaces.sol
    - contracts/modules/DegenerusGameAdvanceModule.sol
    - contracts/modules/DegenerusGameJackpotModule.sol
    - contracts/modules/DegenerusGameMintModule.sol
    - contracts/modules/DegenerusGameLootboxModule.sol

key-decisions:
  - "Kept creditFlip in BurnieCoin's local IBurnieCoinflip interface because BurnieCoin itself calls coinflip.creditFlip for quest rewards"
  - "Removed unused onlyAdmin modifier from BurnieCoin (only consumer was deleted creditLinkReward)"
  - "JackpotModule switched from IDegenerusCoinModule to IDegenerusCoin since creditFlip was stripped from the module interface"

patterns-established:
  - "Direct coinflip crediting: all contracts call BurnieCoinflip.creditFlip directly instead of routing through BurnieCoin"

requirements-completed: [CLN-01, CLN-04]

duration: 10min
completed: 2026-03-30
---

# Phase 146 Plan 01: BurnieCoin Forwarding Wrapper Removal Summary

**Deleted 7 BurnieCoin forwarding wrappers, expanded BurnieCoinflip access control to 4 callers, rewired 8 contracts to call BurnieCoinflip directly**

## Performance

- **Duration:** 10 min
- **Started:** 2026-03-30T03:40:14Z
- **Completed:** 2026-03-30T03:50:46Z
- **Tasks:** 2
- **Files modified:** 10

## Accomplishments
- Expanded BurnieCoinflip.onlyFlipCreditors to accept GAME, BURNIE, AFFILIATE, and ADMIN
- Rewired all coin.creditFlip/creditFlipBatch calls across 5 game modules, Affiliate, Admin, and Game to call BurnieCoinflip directly
- Deleted 7 forwarding functions from BurnieCoin: creditFlip, creditFlipBatch, creditLinkReward, previewClaimCoinflips, coinflipAmount, claimableCoin, coinflipAutoRebuyInfo
- Removed duplicate LinkCreditRecorded event and unused onlyAdmin modifier from BurnieCoin
- Stripped creditFlip/creditFlipBatch from IDegenerusCoinModule interface
- All 62 Solidity files compile successfully

## Task Commits

Each task was committed atomically:

1. **Task 1: Expand BurnieCoinflip access control + update IDegenerusCoinModule** - `8c861114` (feat)
2. **Task 2: Rewire all callers from BurnieCoin to BurnieCoinflip + delete BurnieCoin wrappers** - `81cfbeae` (feat)

## Files Created/Modified
- `contracts/BurnieCoinflip.sol` - Expanded onlyFlipCreditors to 4 callers, updated NatSpec
- `contracts/BurnieCoin.sol` - Deleted 7 forwarding wrappers, LinkCreditRecorded event, onlyAdmin modifier, updated NatSpec
- `contracts/interfaces/DegenerusGameModuleInterfaces.sol` - Removed creditFlip/creditFlipBatch from IDegenerusCoinModule
- `contracts/DegenerusGame.sol` - Changed coin.creditFlip to coinflip.creditFlip
- `contracts/DegenerusAdmin.sol` - Replaced IDegenerusCoinLinkReward with IBurnieCoinflipLinkReward, calls coinflipReward.creditFlip
- `contracts/DegenerusAffiliate.sol` - Added IBurnieCoinflipAffiliate interface and coinflip constant, routes rewards directly
- `contracts/modules/DegenerusGameAdvanceModule.sol` - Changed coin.creditFlip to coinflip.creditFlip (6 call sites)
- `contracts/modules/DegenerusGameJackpotModule.sol` - Added IBurnieCoinflip import + coinflip constant, switched coin type to IDegenerusCoin, rewired 8 call sites
- `contracts/modules/DegenerusGameMintModule.sol` - Added IBurnieCoinflip import + coinflip constant, rewired 3 call sites
- `contracts/modules/DegenerusGameLootboxModule.sol` - Added IBurnieCoinflip import + coinflip constant, rewired 1 call site

## Decisions Made
- Kept creditFlip in BurnieCoin's local IBurnieCoinflip interface because BurnieCoin itself calls BurnieCoinflip.creditFlip for quest rewards -- this is a direct usage, not a forwarding wrapper
- Removed unused onlyAdmin modifier since its only consumer (creditLinkReward) was deleted
- JackpotModule switched from IDegenerusCoinModule to IDegenerusCoin since creditFlip/creditFlipBatch were stripped from the module interface and IDegenerusCoin inherits the remaining functions

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Retained creditFlip in BurnieCoin's local IBurnieCoinflip interface**
- **Found during:** Task 2 (compilation)
- **Issue:** BurnieCoin itself calls IBurnieCoinflip(coinflipContract).creditFlip() for quest rewards at line 738; removing creditFlip from the local interface caused compilation failure
- **Fix:** Kept creditFlip in the local IBurnieCoinflip interface declaration (this is not a forwarding wrapper -- BurnieCoin is a direct consumer of BurnieCoinflip.creditFlip)
- **Files modified:** contracts/BurnieCoin.sol
- **Verification:** npx hardhat compile exits 0
- **Committed in:** 81cfbeae (Task 2 commit)

**2. [Rule 2 - Missing Critical] Removed unused onlyAdmin modifier**
- **Found during:** Task 2 (BurnieCoin wrapper deletion)
- **Issue:** After deleting creditLinkReward, the onlyAdmin modifier had zero consumers
- **Fix:** Deleted the modifier and removed it from the NatSpec modifier hierarchy table
- **Files modified:** contracts/BurnieCoin.sol
- **Verification:** Compilation passes, no references to onlyAdmin remain
- **Committed in:** 81cfbeae (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (1 bug, 1 missing critical)
**Impact on plan:** Both fixes necessary for correctness. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Known Stubs
None

## Next Phase Readiness
- Ready for Plan 02 (unused view removal from DegenerusGame)
- All contracts compile cleanly with the forwarding wrapper removals

---
*Phase: 146-execute-removals*
*Completed: 2026-03-30*
