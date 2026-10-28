# Storage reuse implementation review

> **Historical evidence.** This file records the storage-reuse implementation committed in `c4c1effe5` (2026-10-20; source baseline `fb2540c55`, Solidity 0.8.34). It is not a description of the current
> source. Current layouts and behavior: [Storage reuse](../../../docs/STORAGE-REUSE.md) and
> `scripts/layout/golden/`.

Scope: the R90 Coinflip ring, daily-phase Vault backstop, two BAF records and one
affiliate history/cache word. This is a new-deployment change. The implementation
does not migrate live contracts. Test results and native measurements are separate
evidence; the arguments below are not a machine-checked proof of the protocol.

## Coinflip

- A page is `day / 7`. Its full `page + 1` tag fits in 24 bits throughout the
  supported uint24 day domain. Seven uint32 lanes occupy exactly the low 224 bits;
  the hint occupies only the top byte. Reads require an exact full tag and ignore
  the hint, so a matching seven-bit hint cannot expose another generation.
  Every nonzero ring word has a tag of at least one: allocation sets it and all
  lane/hint writes preserve it. The reuse test therefore subtracts one unchecked;
  multiplying a uint24 tag by seven cannot approach uint256 overflow.
- Ordinary credits only target wall-clock tomorrow. For a fixed target page, its
  chosen home is stable: an overflow marker is written when it spills, and a later
  credit checks that overflow before considering reuse after a claim. Advancing to
  another colliding page cannot be followed by a legitimate credit to the older
  page. This monotonic-credit assumption is part of the design contract.
- A home is reused only when its highest nonzero day is consumed by `lastClaim` or
  expired behind `flipsClaimableDay - 90`. Every other nonzero lane is earlier.
  Both cutoffs are monotonic in reachable production state. All replacements
  initialize a new tag with empty lanes; all merges mask only one amount lane.
- A collision with a live page uses an absolute overflow word. Neither capacity
  nor the number of historical overflow words creates a loop or forces a claim.
  Overflow may grow during exceptional stalls; that is the cost of preserving
  live liabilities without a capacity revert.
- Claims write the economic cursor and bank/carry, never a stake page. There is no
  cached stake writeback that can erase a later credit. The widened loop cursor
  terminates at the last uint24 day. Reads remain proportional to elapsed claim
  days, bounded by 90, and do not scan ring capacity or historical overflow.
- Saturation subtracts the current lane from its cap before comparing the input;
  even a uint256-max automatic credit cannot overflow the addition. Manual
  deposits retain their above-cap revert. Zero credits do not initialize storage.

The independent absolute-day Solidity ledger checks payout, bank, rolling carry,
seed stake, loss rewards, BAF credit, repeated claims and expiry. The separate
codec prototype exercises spills, recovery, marker wrap and every page alignment.

## Vault checkpoint

The backstop runs after daily application and before every branch of the daily
phase. It is a resumable checkpoint: it banks via zero deposit, updates the Game's
stamp only after success, and returns without closing the day. Reversion rolls
back both the bank and stamp. The stamp is a lower bound on the real claim cursor;
independent permissionless settlements can only make a later backstop redundant.

With a checkpoint interval of 45, the stated live recovery bound is 44 + 31 + 1 =
76 resolved days, below 90. Catastrophic terminal jumps can forfeit old positions;
no new Vault external call was added to daily RNG application, gap application or
terminal RNG resolution. Tests cover all daily branches, insufficient continuation
budget, atomic rollback, redundant settlement and adjacent packed fields.

## BAF

Every score/consolation reader checks both absolute bracket and epoch. Adjacent
decades select different parity homes. No defensive revert or old-bracket lookup
is needed in the recorder. Lifetime safety comes from the authenticated callers:

- `Coinflip._claimCoinflipsInternal` derives the bracket from the actual Game level
  plus one. During a closing draw at B it writes B+10, the opposite parity home.
- `runBafJackpot` arms `jackpotWork.kind = 7` at consolidation with Game level B.
  `runDailyPhase` resumes that work before any jackpot daily/phase-ending branch.
  Partial work retains the RNG lock. `_minerAction` selects DailyPhase while that
  lock is held, so a new daily request cannot promote the Game level.
- `runBafAwards` finalizes B only after all awards, then retires the work. Normal
  progression cannot reach Game level B+10, and therefore credit bracket B+20,
  before the closing draw completes. The earlier transition branch cannot already
  be armed: `_endPhase` follows the jackpot daily/ticket legs that BAF precedes.
- Terminal entry retires unpaid continuation work and releases its reservation;
  it does not resume that draw or advance levels into another decade.

This depends on the Game/Coinflip call graph, not on accepting arbitrary bracket
arguments from a hypothetical replacement caller. A test that impersonates Coinflip
and writes B+20 early deliberately overwrites the old home without reverting.
Any future caller or stage-order change must re-establish the lifetime argument.
Consolation claims consume only the total and retain the tags; a stale claim cannot
consume a newer bracket's record. The documented reachable score bound is below
2^155, inside uint168, and subtraction-before-addition also saturates arbitrary
inputs safely. Old consolation expiry is an approved economic change.

## Affiliate

Positive production writers target monotonically increasing Game level + 1.
Game level's only production assignment is `prepareRequestBoundary`'s `level = lvl`,
where `lvl = level + 1`. Mint, foil, whale and AFKing writers all use that next
level, including late claims. Level zero and backward writes are therefore outside
reachable commission state. The library nevertheless returns `(word, 0, 0)` before
the subtraction for those inputs, so they cannot panic or interrupt payout. No
previous-level credit branch is needed. Tests exercise those invalid inputs and
assert that score/denominator remain unchanged while commission credits still occur.
Keeping T and T−1 exact therefore preserves both next-level accrual and current
DGNRS claims. Five clipped older lanes cover every activity-bonus input even
when T is one level ahead. Since the minimum ticket price is 0.01 ETH, any single
500,000-point history lane already saturates that bonus; clipping larger values
cannot change it. A future price decrease requires revisiting this argument.

The 35-bit score cap changes only tracked score and proportional allocations.
The global denominator adds accepted deltas, never excess commission; its sum is
below 2^67 even at 2^32 IDs. Payout, kickback and quest inputs remain uncapped by
this rule. Zero score does not roll history. Level advances preserve the 66-bit
immutable referral cache. The AFKing drain reloads the current word before merging
validated cache fields, preventing stale history from overwriting callback work.
The independent ledger and existing routing tests cover clipping, gaps, caps,
denominator conservation, payouts, ties and stable/unstable referral caches.

## Mutation evidence

`mutations.json` records eight deliberately broken versions of production Coinflip.
The same tests pass without each change and fail with it: missing overflow reads,
missing exact tags, hint destruction on a spill merge, duplicate placement after
recovery, early live-page reuse, a claim writing back cached stake data, discarded
Vault mintable, and doubled Vault mintable. Compiler errors do not count as kills.
All eight were detected; original sources and address pins were restored.

## Limits and release obligations

This review does not establish absolute security or a global gas optimum. Native
gas evidence must identify exact address pins, bytecode, logical prestate, fork
and refund semantics. Whole-call costs must fit the caller's composed allowance,
including exceptional overflow. External sim, website and database consumers
still need their new-deployment schemas/runtime hashes updated; see
`docs/STORAGE-REUSE.md`. Any compiler, codec or caller change requires the affected
checks and benchmarks to be repeated before deployment.
