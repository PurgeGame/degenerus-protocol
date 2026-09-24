# Jackpot-phase quadrant whale passes

September 24, 2026. Implemented alongside the early-bird conversion in the working
tree based on `3a9bbe9c`.

## Award rule

Every quadrant of a jackpot-phase daily ETH draw can convert up to 25% of its
allocated ETH into full prize whale passes. This applies to day one, the middle
day, the final day and a turbo phase. Calculate the usual bucket shares and ETH
winner counts first, including their existing price-unit rounding and solo
remainder allocation.

For an eligible quadrant with allocation `B` and `N` ETH winning slots:

```text
fullPasses = floor(floor(B / 4) / 4.5 ETH)
passCost = fullPasses * 4.5 ETH
ethBudget = B - passCost
ethPerSlot = floor(ethBudget / N)
halfPassClaimUnits = fullPasses * 2
```

The full-pass accounting rate is two shared `HALF_WHALE_PASS_PRICE` units. It is
an entitlement-sizing rate, not a retail purchase or ETH redemption price.
Conversion starts at **18 ETH allocated to that quadrant**. Below that threshold
the whole allocation remains in its ETH prize budget.

| Quadrant allocation | Full passes | Normal ETH prize budget | Credit to futurePrizePool |
| ---: | ---: | ---: | ---: |
| 17 ETH | 0 | 17 ETH | 0 |
| 18 ETH | 1 | 13.5 ETH | 4.5 ETH |
| 20 ETH | 1 | 15.5 ETH | 4.5 ETH |
| 100 ETH | 5 | 77.5 ETH | 22.5 ETH |

The unused part of the 25% allowance stays in the normal ETH prize budget. Any
integer-division dust from splitting that budget among the ETH slots follows the
existing unpaid-budget rules: retained in current on a non-final day, moved to
future when the final day empties current. An empty quadrant with no real or
virtual deity entries receives no pass or ETH award.

## Recipient and randomness

Each qualifying quadrant gets one fresh draw from its own official winning
trait's inventory at the current level. The winner receives all its full passes.
The draw uses the usual real-entry and virtual-deity weights. It may select an
existing ETH winner, and one wallet may win several quadrants. There is no wallet
deduplication or cross-quadrant gold preference for this prize.

The original ETH recipients, indices, slot counts and sampling salts remain
unchanged. The solo ETH recipient continues to be the golden-ticket candidate
when all four main traits are gold; the separate pass winner does not replace it.
This replaces the old solo-only half-pass conversion, without applying another
25% conversion on top of the solo's new allocation.

Each pass draw derives:

```text
bucketEntropy = H(existing effective ETH-draw entropy, quadrant)
passRoot = H(bucketEntropy, keccak256("jackpot-quadrant-whale"), dailyIdx, level)
entryIndex = H(passRoot, 1) mod (realEntryCount + virtualDeityCount)
```

The frozen day index, source inventory and hero-adjusted traits are the ones
already used by the ETH stage. Budget, pass count, ETH winners, caller and wall
time do not enter these seeds. A new pass draw needs no additional VRF request.

## Accounting and implementation

`DegenerusGameJackpotModule._processBucket` runs the original ETH sampler. For a
jackpot-phase quadrant allocated at least 18 ETH, it delegates to
`DegenerusGameWhaleModule.awardWhalePass`. That helper calculates the full-pass
count, draws one recipient, credits `whalePassClaims` and credits the exact pass
cost to `futurePrizePool`. The returned cost is included once in the calling
jackpot stage's current-pool debit. Only the remaining ETH payouts are added to
`claimablePool`.

The same nested helper handles the early-bird award in a separate mode. Early
bird supplies its already-latched half-pass count and retains its existing
gold-preferred draw and nextPool funding. Its award stage moves no pools.
The shared price constant lives in `DegenerusGameStorage`; it adds no storage
slot. This quadrant feature adds no pending state or advance stage.

Both modes use the existing `JackpotWhalePassWin(address,uint256,uint8)` event in
GAME's delegatecall context. Source **5** identifies quadrant conversions;
source **4** continues to identify early-bird awards. Source 1 is the retired
solo-only conversion. Event counts remain half-pass units, even for full-pass
awards. Delivery uses the existing deferred `claimWhalePass` path and its claim
restrictions, without expanding 100-level entitlements during the jackpot stage.

At most four aggregate pass claims are credited in this ETH stage, regardless
of prize size. Empty draws and insufficient quarter budgets skip the award.
Any nested-call failure reverts the complete stage, including pool and claim
writes.

## Verification

The focused suite covers whole-pass boundaries at one-wei precision, exact
accounting and all four day shapes, active-bucket masks, deity-only and mixed
inventories, unchanged ETH draws, amount-independent pass recipients, multiple
quadrants paying the same wallet, golden-ticket candidate ownership and the
previous early-bird behavior. Production advance gas fixtures exercise four
pass awards at 305 ETH slots, large final-day allocations and late calls.

The final affected Foundry run passed **87 tests, zero failures and zero skips**
across ten selected sources and their imported suites. Fuzz tests retained
1,000 cases. This includes the ten early-bird tests after moving its award credit
into the shared whale helper.

| Cold production advance fixture | Call gas |
| --- | ---: |
| Day one, all gold, golden grand and four quadrant pass awards | 9,325,590 |
| Day one, plain board and four quadrant pass awards | 9,431,446 |
| Final day, 600,000 ETH current pool and four large pass awards | 9,322,879 |
| Same final-day case advanced late | 9,325,221 |
| Early-bird 128-recipient converted draw with hero and partial source words | 7,955,028 |

These call measurements exclude transaction intrinsic gas and test assertion
costs. They are below the 10M stage target and the 16,777,216 transaction cap.
The ETH fixtures produce all 305 slots, including repeated recipients; they are
measured stress cases, not a proof of a global gas maximum.

All eleven source/interface gates pass. The storage oracle matches all 27
goldens and shared-slot alignment, with no layout change beyond the earlier
early-bird field. All 33 deployment entries fit EIP-170 under production and
Foundry fixture pins: Jackpot runtime is **24,447 bytes** (129 spare), and Whale
runtime is **24,306 bytes** (270 spare). Production source hashes and runtime
sizes were checked after a forced fresh build.

```sh
python3 scripts/test-foundry-groups.py \
  --file test/fuzz/QuadrantWhalePass.t.sol \
  --file test/fuzz/EarlyBirdWhalePass.t.sol \
  --file test/fuzz/DailyJackpotDayShapes.t.sol \
  --file test/fuzz/JackpotSingleCallCorrectness.t.sol \
  --file test/fuzz/JackpotCombinedPool.t.sol \
  --file test/fuzz/JackpotEightWinnerGroups.t.sol \
  --file test/fuzz/GoldenTicketArmResolve.t.sol \
  --file test/fuzz/GoldenTicketArmedBitParity.t.sol \
  --file test/gas/JackpotDayOneWorstCase.t.sol \
  --file test/gas/EarlyBird128Stress.t.sol \
  --log-dir .audit-test-logs/quadrant-whale-final
```

Raw logs and the test summary are in that ignored local evidence directory.
This was an affected-suite verification; full repository suites and static
analyzers were not rerun for this change.
